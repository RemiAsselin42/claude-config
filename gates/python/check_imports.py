#!/usr/bin/env python
"""Architecture gates for a Python package: import cycles and layer contracts.

Shared by every repo through the reusable workflow .github/workflows/arch-gates.yml,
which runs this file from claude-config at a pinned tag, never from the PR branch.
Each project declares its package and its layers in an `arch-gates.json`:

    {
      "package": "app",
      "layers": [
        {"name": "config",   "modules": ["app", "app.config"]},
        {"name": "adapters", "modules": ["app.db", "app.parsers"]},
        {"name": "web",      "modules": ["app.routes", "app.main"]}
      ]
    }

Layers go from the lowest to the highest. A module may import its own layer or a
lower one; an import that goes up is a violation. An entry covers the module and
its submodules, except the root package entry, which covers only the package
itself: a new subpackage must be classified, it never falls into a layer silently.

Semantics, identical to dependency-cruiser on the frontend (tsPreCompilationDeps:
false): runtime imports only (`if TYPE_CHECKING:` imports are ignored), direct
edges, module-level cycles. grimp parses the files and never executes them.

Ratchet: violations listed in the baseline next to arch-gates.json
(import-cycles-baseline.json, import-layers-baseline.json) are tolerated, any
other one fails. Exit codes:
    0  no new violation
    1  a violation absent from the baseline
    2  a blind spot: a .py file grimp did not analyse, or a module in no layer

Usage:
    python check_imports.py cycles [--config backend/arch-gates.json] [--update-baseline | --init-baseline]
    python check_imports.py layers [--config backend/arch-gates.json] [--update-baseline | --init-baseline]

--update-baseline rewrites the baseline (hooks/protect-gates.js keeps it for the
human); --init-baseline only creates an absent one, which /init-gates uses. The
CI ratchet counts any new baseline as growth, so the owner's label still decides.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections.abc import Callable, Iterable
from pathlib import Path
from typing import Any

import grimp

CYCLES_BASELINE = "import-cycles-baseline.json"
LAYERS_BASELINE = "import-layers-baseline.json"


# --- graph ------------------------------------------------------------------


def discover_packages(package_dir: Path, project_dir: Path) -> list[str]:
    """Roots to hand to grimp: the package plus every namespace package under it.

    grimp does not descend into a PEP 420 namespace package (a directory of .py
    files without __init__.py), so each one is added as a root of its own.
    """
    roots = [".".join(package_dir.relative_to(project_dir).parts)]
    for dirpath, dirnames, filenames in os.walk(package_dir):
        dirnames[:] = [d for d in dirnames if d != "__pycache__"]
        if any(f.endswith(".py") for f in filenames) and "__init__.py" not in filenames:
            roots.append(".".join(Path(dirpath).relative_to(project_dir).parts))
    return list(dict.fromkeys(roots))


def expected_modules(package_dir: Path, project_dir: Path) -> set[str]:
    """Every module the disk holds, read independently of grimp: the safety net."""
    mods: set[str] = set()
    for dirpath, dirnames, filenames in os.walk(package_dir):
        dirnames[:] = [d for d in dirnames if d != "__pycache__"]
        for filename in filenames:
            if filename.endswith(".py"):
                dotted = ".".join(Path(dirpath, filename).relative_to(project_dir).with_suffix("").parts)
                mods.add(dotted.removesuffix(".__init__"))
    return mods


def build_graph(package_dir: Path, project_dir: Path) -> grimp.ImportGraph:
    """Runtime import graph of the package (TYPE_CHECKING imports excluded, no cache)."""
    sys.path.insert(0, str(project_dir))
    return grimp.build_graph(
        *discover_packages(package_dir, project_dir),
        exclude_type_checking_imports=True,
        cache_dir=None,
    )


# --- cycles -----------------------------------------------------------------


def find_cycles(graph: Any) -> list[tuple[str, ...]]:
    """Non-trivial strongly connected components (Tarjan), each as a sorted tuple."""
    succ = {m: graph.find_modules_directly_imported_by(m) for m in graph.modules}
    index: dict[str, int] = {}
    lowlink: dict[str, int] = {}
    on_stack: set[str] = set()
    stack: list[str] = []
    cycles: list[tuple[str, ...]] = []

    def strongconnect(v: str) -> None:
        index[v] = lowlink[v] = len(index)
        stack.append(v)
        on_stack.add(v)
        for w in sorted(succ[v]):
            if w not in index:
                strongconnect(w)
                lowlink[v] = min(lowlink[v], lowlink[w])
            elif w in on_stack:
                lowlink[v] = min(lowlink[v], index[w])
        if lowlink[v] == index[v]:
            component: list[str] = []
            while True:
                w = stack.pop()
                on_stack.discard(w)
                component.append(w)
                if w == v:
                    break
            if len(component) > 1 or v in succ[v]:  # a self-import is a cycle too
                cycles.append(tuple(sorted(component)))

    for module in sorted(graph.modules):
        if module not in index:
            strongconnect(module)
    return sorted(cycles)


# --- layers -----------------------------------------------------------------


def layer_ranker(layers: list[dict[str, Any]], package: str) -> Callable[[str], int | None]:
    """module -> index of its layer (0 = lowest), or None when no entry covers it."""
    exact: dict[str, int] = {}
    subtree: dict[str, int] = {}
    for rank, layer in enumerate(layers):
        for entry in layer["modules"]:
            exact[entry] = rank
            if entry != package:  # the root package covers itself only
                subtree[entry] = rank

    def rank_of(module: str) -> int | None:
        if module in exact:
            return exact[module]
        parts = module.split(".")
        for i in range(len(parts) - 1, 0, -1):  # longest covering ancestor wins
            ancestor = ".".join(parts[:i])
            if ancestor in subtree:
                return subtree[ancestor]
        return None

    return rank_of


def find_upward_edges(graph: Any, rank: Callable[[str], int | None]) -> list[tuple[str, str]]:
    """Direct imports from a lower layer to a higher one."""
    out: list[tuple[str, str]] = []
    for module in sorted(graph.modules):
        r_from = rank(module)
        if r_from is None:
            continue
        for imported in sorted(graph.find_modules_directly_imported_by(module)):
            r_to = rank(imported)
            if r_to is not None and r_from < r_to:
                out.append((module, imported))
    return out


# --- ratchet ----------------------------------------------------------------


def load_baseline(path: Path) -> set[tuple[str, ...]]:
    if not path.exists():
        return set()
    return {tuple(item) for item in json.loads(path.read_text(encoding="utf-8"))}


def ratchet(current: Iterable[tuple[str, ...]], path: Path, freeze: str | None, label: str) -> int:
    """freeze: None runs the gate, "update" rewrites the baseline, "init" only creates an absent one."""
    current = set(current)
    if freeze == "init" and path.exists():
        print(f"ERROR: {path.name} already exists; --init-baseline never overwrites a baseline.", file=sys.stderr)
        return 2
    if freeze:
        path.write_text(json.dumps([list(v) for v in sorted(current)], indent=2) + "\n", encoding="utf-8")
        print(f"{path.name}: {len(current)} {label}(s) frozen.")
        return 0
    baseline = load_baseline(path)
    new = sorted(current - baseline)
    if new:
        print(f"x {len(new)} new {label}(s), absent from {path.name}:", file=sys.stderr)
        for violation in new:
            print(f"  - {' -> '.join(violation)}", file=sys.stderr)
        return 1
    print(f"OK: no new {label}. {len(current)} known {label}(s) tolerated by {path.name}.")
    return 0


# --- main -------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Import cycle and layer gates (see module docstring).")
    parser.add_argument("gate", choices=["cycles", "layers"])
    parser.add_argument("--config", default="arch-gates.json", type=Path)
    freeze = parser.add_mutually_exclusive_group()
    freeze.add_argument("--update-baseline", dest="freeze", action="store_const", const="update", help="freeze the current violations")
    freeze.add_argument("--init-baseline", dest="freeze", action="store_const", const="init", help="create the baseline, refused if it exists")
    args = parser.parse_args(argv)

    config_path = args.config.resolve()
    config = json.loads(config_path.read_text(encoding="utf-8"))
    project_dir = config_path.parent
    package = config["package"]
    package_dir = project_dir.joinpath(*package.split("."))

    sys.setrecursionlimit(10_000)  # Tarjan recurses once per module
    graph = build_graph(package_dir, project_dir)

    missing = expected_modules(package_dir, project_dir) - graph.modules
    if missing:
        print("ERROR: modules grimp did not analyse (blind spot):", file=sys.stderr)
        for module in sorted(missing):
            print(f"  - {module}", file=sys.stderr)
        return 2

    if args.gate == "cycles":
        return ratchet(find_cycles(graph), project_dir / CYCLES_BASELINE, args.freeze, "cycle")

    rank = layer_ranker(config["layers"], package)
    unclassified = sorted(m for m in graph.modules if rank(m) is None)
    if unclassified:
        print(f"ERROR: modules in no layer (classify them in {config_path.name}):", file=sys.stderr)
        for module in unclassified:
            print(f"  - {module}", file=sys.stderr)
        return 2
    return ratchet(find_upward_edges(graph, rank), project_dir / LAYERS_BASELINE, args.freeze, "upward import")


if __name__ == "__main__":
    raise SystemExit(main())
