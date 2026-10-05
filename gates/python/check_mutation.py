#!/usr/bin/env python
"""Mutation gate for a Python package: the mutants the tests do not kill may only shrink.

Shared by every repo through the reusable workflow .github/workflows/mutation-gate.yml,
which runs `mutmut run` in the project, then this file from claude-config at a pinned
tag, never from the PR branch. The project declares what to mutate in its
pyproject.toml, a section hooks/protect-gates.js keeps for the human:

    [tool.mutmut]
    source_paths = ["app/parsers/_bibtex.py"]              # the files to mutate
    also_copy = ["app"]                                     # what the tests import besides
    pytest_add_cli_args_test_selection = ["tests/test_parsers.py"]  # the tests run per mutant

mutmut (3.8; it refuses to run on native Windows, so the proof lives in CI) writes
one mutants/<source path>.meta per mutated file, with the exit code of the tests
against every mutant. This gate reads those files and nothing else:

    not killed   survived (the tests pass on the mutant) and "no tests" (no selected
                 test reaches the mutated line): the same hole seen from two sides,
                 both go in the baseline
    noise        timeout, suspicious, skipped: reported, never counted
    blind spot   no .meta at all, zero mutants, or a mutant "not checked" (the run
                 was interrupted): exit 2, the result cannot be trusted

Ratchet: the names of the not-killed mutants listed in mutation-baseline.json next
to pyproject.toml are tolerated, any other one fails. A missing baseline counts as
empty, so the first run prints every not-killed name: that list is the file to
commit. Its name puts it under the baseline-ratchet workflow: it may only shrink.
Exit codes:
    0  no new not-killed mutant
    1  a not-killed mutant absent from the baseline (`mutmut show <name>` prints its diff)
    2  a blind spot

Usage, after `mutmut run` in the directory holding pyproject.toml and mutants/:
    python check_mutation.py [--project-dir backend] [--update-baseline | --init-baseline]

--update-baseline rewrites the baseline (hooks/protect-gates.js keeps it for the
human); --init-baseline only creates an absent one.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

BASELINE = "mutation-baseline.json"

# mutmut/stats.py, status_by_exit_code (3.8.0); any other code is "suspicious" there
# too. The end-to-end test runs the real tool against this table.
STATUS_BY_EXIT_CODE: dict[int | None, str] = {
    None: "not checked",
    0: "survived",
    1: "killed",
    3: "killed",  # internal error in pytest counts as a kill, as in mutmut
    5: "no tests",
    33: "no tests",
    34: "skipped",
    35: "suspicious",
    36: "timeout",
    -24: "timeout",
    24: "timeout",
    152: "timeout",
    255: "timeout",
}
NOT_KILLED = ("survived", "no tests")


def status(exit_code: int | None) -> str:
    return STATUS_BY_EXIT_CODE.get(exit_code, "suspicious")


def read_results(project_dir: Path) -> dict[str, str]:
    """Mutant name -> status, from every mutants/**/*.meta under the project."""
    results: dict[str, str] = {}
    for meta in sorted((project_dir / "mutants").rglob("*.meta")):
        data = json.loads(meta.read_text(encoding="utf-8"))
        for name, code in data["exit_code_by_key"].items():
            results[name] = status(code)
    return results


def not_killed(results: dict[str, str]) -> list[str]:
    return sorted(name for name, st in results.items() if st in NOT_KILLED)


def blind_spot(results: dict[str, str]) -> str | None:
    """Why the result cannot be trusted, or None."""
    if not results:
        return "no mutant found under mutants/: run `mutmut run` first, or [tool.mutmut] names nothing to mutate"
    unchecked = sum(1 for st in results.values() if st == "not checked")
    if unchecked:
        return f"{unchecked} mutant(s) not checked: the run was interrupted, rerun it"
    return None


def summary(results: dict[str, str]) -> str:
    counts = Counter(results.values())
    order = ("killed", "survived", "no tests", "timeout", "suspicious", "skipped", "not checked")
    parts = [f"{counts[st]} {st}" for st in order if counts[st]]
    return f"{len(results)} mutants: " + ", ".join(parts)


def load_baseline(path: Path) -> set[str]:
    if not path.exists():
        return set()
    return set(json.loads(path.read_text(encoding="utf-8")))


def ratchet(current: list[str], path: Path, freeze: str | None) -> int:
    """freeze: None runs the gate, "update" rewrites the baseline, "init" only creates an absent one."""
    if freeze == "init" and path.exists():
        print(f"ERROR: {path.name} already exists; --init-baseline never overwrites a baseline.", file=sys.stderr)
        return 2
    if freeze:
        path.write_text(json.dumps(sorted(current), indent=2) + "\n", encoding="utf-8")
        print(f"{path.name}: {len(current)} not-killed mutant(s) frozen.")
        return 0
    baseline = load_baseline(path)
    new = sorted(set(current) - baseline)
    gone = sorted(baseline - set(current))
    if gone:
        print(f"{len(gone)} baselined mutant(s) now killed; remove them from {path.name}:")
        for name in gone:
            print(f"  - {name}")
    if new:
        where = "absent from" if path.exists() else "and no"
        print(f"x {len(new)} not-killed mutant(s) {where} {path.name} (`mutmut show <name>` prints the diff):", file=sys.stderr)
        for name in new:
            print(f"  - {name}", file=sys.stderr)
        if not path.exists():
            print(f"To start from here, commit {path.name} with:", file=sys.stderr)
            print(json.dumps(new, indent=2), file=sys.stderr)
        return 1
    print(f"OK: no new not-killed mutant. {len(current)} known one(s) tolerated by {path.name}.")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Mutation gate (see module docstring).")
    parser.add_argument("--project-dir", default=".", type=Path, help="directory holding pyproject.toml, mutants/ and the baseline")
    freeze = parser.add_mutually_exclusive_group()
    freeze.add_argument("--update-baseline", dest="freeze", action="store_const", const="update", help="freeze the current not-killed mutants")
    freeze.add_argument("--init-baseline", dest="freeze", action="store_const", const="init", help="create the baseline, refused if it exists")
    args = parser.parse_args(argv)

    project_dir = args.project_dir.resolve()
    results = read_results(project_dir)
    reason = blind_spot(results)
    if reason:
        print(f"ERROR: {reason}", file=sys.stderr)
        return 2
    print(summary(results))
    return ratchet(not_killed(results), project_dir / BASELINE, args.freeze)


if __name__ == "__main__":
    raise SystemExit(main())
