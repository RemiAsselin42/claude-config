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
one mutants/<source path>.meta per mutated file: the exit code of the tests against
every mutant, and a hash of every function's source. This gate reads those files
and nothing else:

    killed       killed, or caught by the type checker
    not killed   survived (the tests pass on the mutant) and "no tests" (no selected
                 test reaches the mutated line): the same hole seen from two sides,
                 both go in the baseline
    noise        timeout, suspicious, skipped, segfault: reported, never counted
    blind spot   no .meta at all, zero mutants, a mutant not checked or interrupted
                 (the run did not complete), or not one decisive result: exit 2

Ratchet: mutation-baseline.json next to pyproject.toml lists the not-killed mutants
as [name, hash of the function's source] pairs. Mutant names are positional
(x_<function>__mutmut_<n>): an edit to the function renumbers them, and a new
survivor could inherit a baselined name, so a name is tolerated only while its
function is unchanged. A missing baseline counts as empty: the first run prints
every pair, that list is the file to commit. Its name puts it under the
baseline-ratchet workflow: it may only shrink. Exit codes:
    0  no new not-killed mutant
    1  a not-killed mutant absent from the baseline, or whose function changed
       (`mutmut show <name>` prints its diff)
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

# mutmut/stats.py, status_by_exit_code (3.8.0), any other code being "suspicious"
# there too. tests/python/test_check_mutation.py compares this copy with the real one.
STATUS_BY_EXIT_CODE: dict[int | None, str] = {
    1: "killed",
    3: "killed",  # internal error in pytest counts as a kill, as in mutmut
    0: "survived",
    5: "no tests",
    2: "check was interrupted by user",
    None: "not checked",
    33: "no tests",
    34: "skipped",
    35: "suspicious",
    36: "timeout",
    37: "caught by type check",
    -24: "timeout",
    24: "timeout",
    152: "timeout",
    255: "timeout",
    -11: "segfault",
    -9: "segfault",
}
KILLED = ("killed", "caught by type check")
NOT_KILLED = ("survived", "no tests")
UNTRUSTED = ("not checked", "check was interrupted by user")

Entry = tuple[str, str]  # (mutant name, hash of its function's source)


def status(exit_code: int | None) -> str:
    return STATUS_BY_EXIT_CODE.get(exit_code, "suspicious")


def function_key(mutant_name: str) -> str:
    """The key of hash_by_function_name for a mutant: pkg.calc.x_add__mutmut_3 -> x_add."""
    return mutant_name.partition("__mutmut_")[0].rpartition(".")[2]


def read_results(project_dir: Path) -> dict[str, tuple[str, str]]:
    """Mutant name -> (status, function hash), from every mutants/**/*.meta under the project."""
    results: dict[str, tuple[str, str]] = {}
    for meta in sorted((project_dir / "mutants").rglob("*.meta")):
        data = json.loads(meta.read_text(encoding="utf-8"))
        hashes = data.get("hash_by_function_name", {})
        for name, code in data["exit_code_by_key"].items():
            results[name] = (status(code), str(hashes.get(function_key(name), "")))
    return results


def not_killed(results: dict[str, tuple[str, str]]) -> list[Entry]:
    return sorted((name, h) for name, (st, h) in results.items() if st in NOT_KILLED)


def blind_spot(results: dict[str, tuple[str, str]]) -> str | None:
    """Why the result cannot be trusted, or None."""
    if not results:
        return "no mutant found under mutants/: run `mutmut run` first, or [tool.mutmut] names nothing to mutate"
    statuses = [st for st, _ in results.values()]
    untrusted = sum(1 for st in statuses if st in UNTRUSTED)
    if untrusted:
        return f"{untrusted} mutant(s) not checked or interrupted: the run did not complete, rerun it"
    if not any(st in KILLED or st in NOT_KILLED for st in statuses):
        return "not one decisive result: every mutant timed out, was skipped, crashed or is suspicious; nothing to judge"
    return None


def summary(results: dict[str, tuple[str, str]]) -> str:
    counts = Counter(st for st, _ in results.values())
    order = ("killed", "caught by type check", "survived", "no tests", "timeout", "suspicious", "skipped", "segfault")
    parts = [f"{counts[st]} {st}" for st in order if counts[st]]
    return f"{len(results)} mutants: " + ", ".join(parts)


def load_baseline(path: Path) -> set[Entry]:
    if not path.exists():
        return set()
    return {(str(name), str(h)) for name, h in json.loads(path.read_text(encoding="utf-8"))}


def ratchet(current: list[Entry], path: Path, freeze: str | None) -> int:
    """freeze: None runs the gate, "update" rewrites the baseline, "init" only creates an absent one."""
    if freeze == "init" and path.exists():
        print(f"ERROR: {path.name} already exists; --init-baseline never overwrites a baseline.", file=sys.stderr)
        return 2
    if freeze:
        path.write_text(json.dumps([list(e) for e in sorted(current)], indent=2) + "\n", encoding="utf-8")
        print(f"{path.name}: {len(current)} not-killed mutant(s) frozen.")
        return 0
    baseline = load_baseline(path)
    known_names = {name for name, _ in baseline}
    new = sorted(set(current) - baseline)
    gone = sorted(baseline - set(current))
    if gone:
        print(f"{len(gone)} baselined entry(ies) no longer current (killed now, or the function changed); remove them from {path.name}:")
        for name, _ in gone:
            print(f"  - {name}")
    if new:
        where = "absent from" if path.exists() else "and no"
        print(f"x {len(new)} not-killed mutant(s) {where} {path.name} (`mutmut show <name>` prints the diff):", file=sys.stderr)
        for name, _ in new:
            why = "its function changed since the baseline: re-examine" if name in known_names else "new"
            print(f"  - {name}  ({why})", file=sys.stderr)
        if not path.exists():
            print(f"To start from here, commit {path.name} with:", file=sys.stderr)
            print(json.dumps([list(e) for e in new], indent=2), file=sys.stderr)
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
