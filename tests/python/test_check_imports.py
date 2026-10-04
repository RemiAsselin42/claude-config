"""Tests for gates/python/check_imports.py.

Run (grimp parses statically, no project install needed):
    uv run --no-project --with grimp==3.14 --with pytest pytest tests/python -q

1. Algorithms on toy graphs: cycles (Tarjan), upward edges, layer ranking.
2. Disk + grimp on temporary trees: namespace packages, the safety net, TYPE_CHECKING.
3. main() end to end: exit codes 0 / 1 / 2 and the baselines, as CI runs it.
"""

from __future__ import annotations

import contextlib
import importlib
import importlib.util
import json
import sys
from collections.abc import Iterator
from pathlib import Path

import grimp
import pytest

_SCRIPT = Path(__file__).resolve().parents[2] / "gates" / "python" / "check_imports.py"
_spec = importlib.util.spec_from_file_location("check_imports", _SCRIPT)
assert _spec and _spec.loader
ci = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ci)


class FakeGraph:
    """Just what the gates read: `modules` and direct imports."""

    def __init__(self, succ: dict[str, set[str]]) -> None:
        nodes = set(succ).union(*succ.values()) if succ else set()
        self._succ = {n: set(succ.get(n, set())) for n in nodes}

    @property
    def modules(self) -> set[str]:
        return set(self._succ)

    def find_modules_directly_imported_by(self, module: str) -> set[str]:
        return set(self._succ[module])


# --- 1. toy graphs -----------------------------------------------------------


def test_three_node_cycle() -> None:
    assert ci.find_cycles(FakeGraph({"a": {"b"}, "b": {"c"}, "c": {"a"}})) == [("a", "b", "c")]


def test_self_import_is_a_cycle() -> None:
    assert ci.find_cycles(FakeGraph({"a": {"a"}})) == [("a",)]


def test_diamond_is_not_a_cycle() -> None:
    assert ci.find_cycles(FakeGraph({"a": {"b", "c"}, "b": {"d"}, "c": {"d"}, "d": set()})) == []


def test_two_disjoint_cycles_plus_acyclic_nodes() -> None:
    graph = FakeGraph({"a": {"b"}, "b": {"a"}, "c": {"d"}, "d": {"c"}, "e": {"a"}, "f": set()})
    assert ci.find_cycles(graph) == [("a", "b"), ("c", "d")]


def test_no_edges_no_cycle() -> None:
    assert ci.find_cycles(FakeGraph({"a": set(), "b": set()})) == []


def _rank(mapping: dict[str, int]):
    return mapping.get


def test_upward_edge_is_flagged() -> None:
    assert ci.find_upward_edges(FakeGraph({"low": {"high"}}), _rank({"low": 0, "high": 1})) == [("low", "high")]


def test_downward_and_same_layer_edges_are_allowed() -> None:
    graph = FakeGraph({"high": {"low"}, "a": {"b"}, "b": {"a"}})
    assert ci.find_upward_edges(graph, _rank({"low": 0, "high": 1, "a": 0, "b": 0})) == []


def test_unclassified_source_is_skipped() -> None:
    assert ci.find_upward_edges(FakeGraph({"x": {"high"}}), _rank({"high": 1})) == []


LAYERS = [
    {"name": "config", "modules": ["app", "app.config"]},
    {"name": "adapters", "modules": ["app.parsers"]},
    {"name": "web", "modules": ["app.routes", "app.main"]},
]


def test_an_entry_covers_its_submodules() -> None:
    rank = ci.layer_ranker(LAYERS, "app")
    assert rank("app.config") == 0
    assert rank("app.parsers._pdf") == 1
    assert rank("app.routes.papers.detail") == 2


def test_the_root_package_covers_only_itself() -> None:
    # fragile case: "app" sits in a layer, yet a new subpackage must not fall into it
    rank = ci.layer_ranker(LAYERS, "app")
    assert rank("app") == 0
    assert rank("app.newpkg") is None
    assert rank("app.newpkg.foo") is None
    assert rank("app.mainframe") is None  # a prefix of a name is not an ancestor


def test_longest_covering_entry_wins() -> None:
    rank = ci.layer_ranker([{"name": "l0", "modules": ["app.x.low"]}, {"name": "l1", "modules": ["app.x"]}], "app")
    assert rank("app.x.low.deep") == 0
    assert rank("app.x.other") == 1


# --- 2. disk + grimp -----------------------------------------------------------


def _write(base: Path, rel: str, content: str = "") -> None:
    path = base / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


@contextlib.contextmanager
def _isolated(root: Path, top: str) -> Iterator[None]:
    """Undo the sys.path / sys.modules changes grimp and the gate make."""
    saved = list(sys.path)
    try:
        yield
    finally:
        sys.path[:] = saved
        for name in [n for n in sys.modules if n == top or n.startswith(f"{top}.")]:
            del sys.modules[name]
        importlib.invalidate_caches()


def test_discover_finds_a_new_namespace_package(tmp_path: Path) -> None:
    _write(tmp_path, "discpkg/__init__.py")
    _write(tmp_path, "discpkg/freshpkg/m.py", "x = 1\n")
    roots = ci.discover_packages(tmp_path / "discpkg", tmp_path)
    assert roots == ["discpkg", "discpkg.freshpkg"]


def test_cycle_inside_a_namespace_subpackage_is_caught(tmp_path: Path) -> None:
    _write(tmp_path, "gatepkg/__init__.py")
    _write(tmp_path, "gatepkg/routers/a.py", "import gatepkg.routers.b\n")
    _write(tmp_path, "gatepkg/routers/b.py", "import gatepkg.routers.a\n")
    with _isolated(tmp_path, "gatepkg"):
        cycles = ci.find_cycles(ci.build_graph(tmp_path / "gatepkg", tmp_path))
    assert ("gatepkg.routers.a", "gatepkg.routers.b") in cycles


def test_safety_net_sees_what_grimp_alone_misses(tmp_path: Path) -> None:
    _write(tmp_path, "misspkg/__init__.py")
    _write(tmp_path, "misspkg/nspkg/hidden.py", "v = 1\n")
    expected = ci.expected_modules(tmp_path / "misspkg", tmp_path)
    with _isolated(tmp_path, "misspkg"):
        sys.path.insert(0, str(tmp_path))
        incomplete = grimp.build_graph("misspkg", cache_dir=None).modules
    assert "misspkg.nspkg.hidden" in expected - incomplete


def test_type_checking_only_cycle_is_not_a_runtime_cycle(tmp_path: Path) -> None:
    _write(tmp_path, "tcpkg/__init__.py")
    _write(tmp_path, "tcpkg/a.py", "from typing import TYPE_CHECKING\n\nif TYPE_CHECKING:\n    from tcpkg import b\n")
    _write(tmp_path, "tcpkg/b.py", "from tcpkg import a\n")
    with _isolated(tmp_path, "tcpkg"):
        assert ci.find_cycles(ci.build_graph(tmp_path / "tcpkg", tmp_path)) == []
        sys.path.insert(0, str(tmp_path))
        with_types = grimp.build_graph("tcpkg", exclude_type_checking_imports=False, cache_dir=None)
    assert ci.find_cycles(with_types) == [("tcpkg.a", "tcpkg.b")]


# --- 3. main() end to end ------------------------------------------------------


@pytest.fixture
def project(tmp_path: Path) -> Path:
    """backend/ with app/{config,parsers/,routes/ (namespace),main}, layered like LAYERS."""
    b = tmp_path / "backend"
    _write(b, "app/__init__.py")
    _write(b, "app/config.py", "X = 1\n")
    _write(b, "app/parsers/__init__.py")
    _write(b, "app/parsers/pdf.py", "from app import config\n")
    _write(b, "app/routes/papers.py", "from app.parsers import pdf\n")  # namespace package
    _write(b, "app/main.py", "from app.routes import papers\n")
    _write(b, "arch-gates.json", json.dumps({"package": "app", "layers": LAYERS}))
    return b


def _gate(project: Path, gate: str, *extra: str) -> int:
    with _isolated(project, "app"):
        return ci.main([gate, "--config", str(project / "arch-gates.json"), *extra])


def test_clean_project_is_green(project: Path) -> None:
    assert _gate(project, "cycles") == 0
    assert _gate(project, "layers") == 0


def test_new_upward_import_is_red_then_tolerated_once_baselined(project: Path) -> None:
    _write(project, "app/config.py", "from app.routes import papers\n")  # config -> web: up, and a cycle
    assert _gate(project, "layers") == 1
    assert _gate(project, "cycles") == 1
    assert _gate(project, "layers", "--update-baseline") == 0
    assert json.loads((project / "import-layers-baseline.json").read_text()) == [["app.config", "app.routes.papers"]]
    assert _gate(project, "layers") == 0
    _write(project, "app/parsers/pdf.py", "from app import main\n")  # a second, new one
    assert _gate(project, "layers") == 1


def test_init_baseline_creates_but_never_overwrites(project: Path) -> None:
    _write(project, "app/config.py", "from app.routes import papers\n")
    baseline = project / "import-layers-baseline.json"
    assert _gate(project, "layers", "--init-baseline") == 0
    assert json.loads(baseline.read_text()) == [["app.config", "app.routes.papers"]]
    baseline.write_text("[]\n")  # an existing baseline, even an emptier one
    assert _gate(project, "layers", "--init-baseline") == 2
    assert baseline.read_text() == "[]\n"
    assert _gate(project, "layers") == 1


def test_a_draft_config_elsewhere_runs_against_the_project(project: Path, tmp_path: Path) -> None:
    # /init-gates drafts layers in its scratchpad and probes them before any gate file exists
    draft = tmp_path / "scratch" / "draft.json"
    draft.parent.mkdir()
    draft.write_text(json.dumps({"package": "app", "layers": LAYERS[::-1]}))  # upside down: every import goes up
    (project / "arch-gates.json").unlink()
    with _isolated(project, "app"):
        code = ci.main(["layers", "--config", str(draft), "--project-dir", str(project)])
    assert code == 1
    assert not (project / "import-layers-baseline.json").exists()
    assert not (draft.parent / "import-layers-baseline.json").exists()


def test_module_in_no_layer_is_a_blind_spot(project: Path) -> None:
    _write(project, "app/newpkg/foo.py", "Y = 2\n")
    assert _gate(project, "layers") == 2
    assert _gate(project, "cycles") == 0  # the cycles gate has nothing to classify
