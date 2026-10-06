#!/usr/bin/env python
"""Quality gates for a package: cyclomatic complexity and duplication may only shrink.

Shared by every repo through the reusable workflows .github/workflows/quality-python.yml
and quality-frontend.yml, which run the tools with the rule imposed on the command line
(ruff check --select C901, eslint --rule complexity, jscpd --reporters json) and then
this file from claude-config at a pinned tag, never from the PR branch. Nothing changes
in the repo's own ruff or eslint configuration: this gate reads the tools' JSON reports
and ratchets them against two baselines next to pyproject.toml or package.json.

complexity   one entry per function above the threshold: [file, function, complexity].
             ruff names the function; eslint names it when it can ("Function 'x'",
             "Method 'y'") and otherwise says "Arrow function": the same label in the
             same file gets an ordinal (" #2", " #3") by order of appearance, so an
             ordinal only moves when a violation is added or removed before it.
             A function absent from the baseline fails; a known one fails when its
             complexity grew; one that shrank passes and is reported, shrink the baseline.
duplication  one entry per clone jscpd reports: [fingerprint, format, lines, file A,
             file B]. The fingerprint is a hash of the duplicated text, whitespace
             collapsed, so it survives a move of the lines or of the file; it changes
             when the duplicated text changes, which is a different clone. A clone
             absent from the baseline fails.

Exit codes:
    0  nothing new
    1  a new violation, or a known function that got more complex
    2  a blind spot: the report is missing or not the tool's format

Usage, from the directory holding the baselines (or --project-dir):
    python check_quality.py complexity --tool ruff   --report ruff.json   [--update-baseline | --init-baseline]
    python check_quality.py complexity --tool eslint --report eslint.json [--update-baseline | --init-baseline]
    python check_quality.py duplication --report .jscpd/jscpd-report.json [--update-baseline | --init-baseline]

--update-baseline rewrites a baseline (hooks/protect-gates.js keeps it for the human);
--init-baseline only creates an absent one. A missing baseline counts as empty.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path

COMPLEXITY_BASELINE = "complexity-baseline.json"
DUPLICATION_BASELINE = "duplication-baseline.json"

RUFF_MESSAGE = re.compile(r"^`(?P<name>[^`]+)` is too complex \((?P<value>\d+) > \d+\)$")
ESLINT_MESSAGE = re.compile(r"^(?P<label>.+?) has a complexity of (?P<value>\d+)\. Maximum allowed is \d+\.$")


class BadReport(Exception):
    """The report is not what the tool writes."""


def relative(path: str, project_dir: Path) -> str:
    """A report path, absolute or not, as a /-separated path relative to the project when it is under it."""
    p = Path(path.replace("\\", "/"))
    try:
        p = p.resolve().relative_to(project_dir.resolve())
    except (ValueError, OSError):
        pass
    return p.as_posix()


def with_ordinals(found: list[tuple[str, str, int, int]]) -> list[tuple[str, str, int]]:
    """(file, label, value, line) -> (file, label[ #n], value): the n-th same label in a file, by line."""
    seen: Counter[tuple[str, str]] = Counter()
    entries: list[tuple[str, str, int]] = []
    for file, label, value, _line in sorted(found, key=lambda f: (f[0], f[3])):
        seen[(file, label)] += 1
        n = seen[(file, label)]
        entries.append((file, label if n == 1 else f"{label} #{n}", value))
    return sorted(entries)


def read_ruff(report: Path, project_dir: Path) -> list[tuple[str, str, int]]:
    data = json.loads(report.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise BadReport(f"{report}: ruff --output-format json writes a list of diagnostics")
    found = []
    for d in data:
        if d.get("code") != "C901":
            continue
        m = RUFF_MESSAGE.match(d["message"])
        if not m:
            raise BadReport(f"{report}: unexpected C901 message {d['message']!r}")
        found.append((relative(d["filename"], project_dir), m["name"], int(m["value"]), int(d["location"]["row"])))
    return with_ordinals(found)


def read_eslint(report: Path, project_dir: Path) -> list[tuple[str, str, int]]:
    data = json.loads(report.read_text(encoding="utf-8"))
    if not isinstance(data, list) or any("messages" not in f for f in data):
        raise BadReport(f"{report}: eslint --format json writes a list of files with messages")
    found = []
    for f in data:
        for msg in f["messages"]:
            if msg.get("ruleId") != "complexity":
                continue
            m = ESLINT_MESSAGE.match(msg["message"])
            if not m:
                raise BadReport(f"{report}: unexpected complexity message {msg['message']!r}")
            found.append((relative(f["filePath"], project_dir), m["label"], int(m["value"]), int(msg["line"])))
    return with_ordinals(found)


def fingerprint(fragment: str) -> str:
    text = "\n".join(line.strip() for line in fragment.splitlines() if line.strip())
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:12]


def read_jscpd(report: Path) -> list[tuple[str, str, int, str, str]]:
    data = json.loads(report.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or "duplicates" not in data:
        raise BadReport(f"{report}: jscpd --reporters json writes an object with a duplicates list")
    entries = []
    for d in data["duplicates"]:
        a, b = d["firstFile"]["name"].replace("\\", "/"), d["secondFile"]["name"].replace("\\", "/")
        entries.append((fingerprint(d["fragment"]), d["format"], int(d["lines"]), a, b))
    return sorted(entries)


# --- ratchets ----------------------------------------------------------------------


def load_baseline(path: Path) -> list[list]:
    if not path.exists():
        return []
    return json.loads(path.read_text(encoding="utf-8"))


def write_baseline(path: Path, entries: list, freeze: str, what: str) -> int:
    if freeze == "init" and path.exists():
        print(f"ERROR: {path.name} already exists; --init-baseline never overwrites a baseline.", file=sys.stderr)
        return 2
    path.write_text(json.dumps([list(e) for e in entries], indent=2) + "\n", encoding="utf-8")
    print(f"{path.name}: {len(entries)} {what}(s) frozen.")
    return 0


def ratchet_complexity(current: list[tuple[str, str, int]], path: Path, freeze: str | None) -> int:
    if freeze:
        return write_baseline(path, current, freeze, "function above the threshold")
    baseline = {(file, label): int(value) for file, label, value in load_baseline(path)}
    now = {(file, label): value for file, label, value in current}
    new = [(k, v) for k, v in sorted(now.items()) if k not in baseline]
    grew = [(k, baseline[k], v) for k, v in sorted(now.items()) if k in baseline and v > baseline[k]]
    shrank = [(k, baseline[k], v) for k, v in sorted(now.items()) if k in baseline and v < baseline[k]]
    gone = sorted(k for k in baseline if k not in now)
    for (file, label), old, v in shrank:
        print(f"{file}: {label} went from {old} to {v}; lower it in {path.name}")
    for file, label in gone:
        print(f"{file}: {label} is no longer above the threshold; remove it from {path.name}")
    if new or grew:
        print(f"x complexity: {len(new)} new function(s) above the threshold, {len(grew)} known one(s) more complex than {path.name} allows:", file=sys.stderr)
        for (file, label), v in new:
            print(f"  - {file}: {label} = {v}  (new)", file=sys.stderr)
        for (file, label), old, v in grew:
            print(f"  - {file}: {label} = {v}  (was {old})", file=sys.stderr)
        if not path.exists():
            print(f"To start from here, commit {path.name} with:", file=sys.stderr)
            print(json.dumps([[*k, v] for k, v in new], indent=2), file=sys.stderr)
        return 1
    print(f"OK: complexity, nothing new. {len(now)} function(s) above the threshold tolerated by {path.name}.")
    return 0


def ratchet_duplication(current: list[tuple[str, str, int, str, str]], path: Path, freeze: str | None) -> int:
    if freeze:
        return write_baseline(path, current, freeze, "clone")
    baseline = {str(e[0]) for e in load_baseline(path)}
    now = {e[0]: e for e in current}
    new = [now[k] for k in sorted(now) if k not in baseline]
    gone = sorted(baseline - set(now))
    if gone:
        print(f"{len(gone)} baselined clone(s) no longer found; remove them from {path.name}: {', '.join(gone)}")
    if new:
        print(f"x duplication: {len(new)} clone(s) absent from {path.name}:", file=sys.stderr)
        for fp, fmt, lines, a, b in new:
            print(f"  - {fp}  {fmt}, {lines} lines: {a} <> {b}", file=sys.stderr)
        if not path.exists():
            print(f"To start from here, commit {path.name} with:", file=sys.stderr)
            print(json.dumps([list(e) for e in new], indent=2), file=sys.stderr)
        return 1
    print(f"OK: duplication, nothing new. {len(now)} known clone(s) tolerated by {path.name}.")
    return 0


# --- main --------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Complexity and duplication gates (see module docstring).")
    parser.add_argument("gate", choices=["complexity", "duplication"])
    parser.add_argument("--tool", choices=["ruff", "eslint"], help="complexity: which tool wrote the report")
    parser.add_argument("--report", required=True, type=Path, help="the tool's JSON report, relative to the project dir unless absolute")
    parser.add_argument("--project-dir", default=".", type=Path, help="directory holding the baselines; report paths are made relative to it")
    freeze = parser.add_mutually_exclusive_group()
    freeze.add_argument("--update-baseline", dest="freeze", action="store_const", const="update", help="freeze the current violations")
    freeze.add_argument("--init-baseline", dest="freeze", action="store_const", const="init", help="create the baseline, refused if it exists")
    args = parser.parse_args(argv)
    if args.gate == "complexity" and not args.tool:
        parser.error("complexity needs --tool ruff|eslint")

    project_dir = args.project_dir.resolve()
    report = args.report if args.report.is_absolute() else project_dir / args.report
    if not report.exists():
        print(f"ERROR: report {report} not found: run the tool first.", file=sys.stderr)
        return 2
    try:
        if args.gate == "duplication":
            current = read_jscpd(report)
            print(f"{len(current)} clone(s) in the report.")
            return ratchet_duplication(current, project_dir / DUPLICATION_BASELINE, args.freeze)
        reader = read_ruff if args.tool == "ruff" else read_eslint
        functions = reader(report, project_dir)
        print(f"{len(functions)} function(s) above the threshold in the report.")
        return ratchet_complexity(functions, project_dir / COMPLEXITY_BASELINE, args.freeze)
    except (BadReport, json.JSONDecodeError, KeyError, TypeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
