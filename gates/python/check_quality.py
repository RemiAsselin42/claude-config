#!/usr/bin/env python
"""Quality gates for a package: cyclomatic complexity and duplication may only shrink.

Shared by every repo through the reusable workflows .github/workflows/quality-python.yml
and quality-frontend.yml, which run the tools with the rule imposed on the command line
(ruff check --select C901, eslint --rule complexity, jscpd --reporters json --absolute)
and then this file from claude-config at a pinned tag, never from the PR branch. Nothing
changes in the repo's own ruff or eslint configuration: this gate reads the tools' JSON
reports and ratchets them against two baselines next to pyproject.toml or package.json.

complexity   one entry per function above the threshold: [file, function, complexity].
             ruff names the function; eslint names it when it can ("Function 'x'",
             "Method 'y'") and otherwise says "Arrow function": the same label in the
             same file gets an ordinal (" #2", " #3") by order of appearance. Known
             limit: an ordinal is a position, not an identity. When an earlier anonymous
             function drops below the threshold in the same change that makes a later
             one grow up to its value, the two cancel out; naming the function is the
             fix, and the better code. A function absent from the baseline fails; a known
             one fails when its complexity grew; one that shrank passes and is reported,
             so the baseline can follow (the CI ratchet reads a lower value as a shrink).
duplication  one entry per clone jscpd reports: [fingerprint, format, lines, file A,
             file B]. The fingerprint is a hash of the duplicated text, whitespace
             collapsed, so it survives a move of the lines or of the file; it changes
             when the duplicated text changes, which is a different clone. The ratchet
             counts the clones per fingerprint: a new fingerprint fails, and so does one
             more copy of a known block (jscpd reports every pair).
blind spots  the report is missing or not the tool's format, or a file the tool could
             not parse (ruff invalid-syntax, eslint fatal): exit 2, nothing is judged.

Exit codes:
    0  nothing new
    1  a new violation, a known function that got more complex, one more copy of a clone
    2  a blind spot

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
RUFF_PARSE_ERROR = {None, "invalid-syntax", "E999"}

Function = tuple[str, str, int]  # (file, label, complexity)
Clone = tuple[str, str, int, str, str]  # (fingerprint, format, lines, file A, file B)


class BadReport(Exception):
    """The report is not what the tool writes, or the tool could not do its job."""


def relative(path: str, project_dir: Path) -> str:
    """A report path, absolute or not, as a /-separated path relative to the project when it is under it."""
    path = str(path)
    if path.startswith("\\\\?\\"):  # jscpd --absolute on Windows
        path = path[4:]
    p = Path(path.replace("\\", "/"))
    try:
        p = p.resolve().relative_to(project_dir.resolve())
    except (ValueError, OSError):
        pass
    return p.as_posix()


def with_ordinals(found: list[tuple[str, str, int, int]]) -> list[Function]:
    """(file, label, value, line) -> (file, label[ #n], value): the n-th same label in a file, by line."""
    seen: Counter[tuple[str, str]] = Counter()
    entries: list[Function] = []
    for file, label, value, _line in sorted(found, key=lambda f: (f[0], f[3])):
        seen[(file, label)] += 1
        n = seen[(file, label)]
        entries.append((file, label if n == 1 else f"{label} #{n}", value))
    return sorted(entries)


def read_ruff(report: Path, project_dir: Path) -> list[Function]:
    data = json.loads(report.read_text(encoding="utf-8"))
    if not isinstance(data, list) or any(not isinstance(d, dict) for d in data):
        raise BadReport(f"{report}: ruff --output-format json writes a list of diagnostics")
    unparsed = sorted({relative(d["filename"], project_dir) for d in data if d.get("code") in RUFF_PARSE_ERROR})
    if unparsed:
        raise BadReport(f"ruff could not parse {', '.join(unparsed)}: nothing is judged until it does")
    found = []
    for d in data:
        if d.get("code") != "C901":
            continue
        m = RUFF_MESSAGE.match(d["message"])
        if not m:
            raise BadReport(f"{report}: unexpected C901 message {d['message']!r}")
        found.append((relative(d["filename"], project_dir), m["name"], int(m["value"]), int(d["location"]["row"])))
    return with_ordinals(found)


def read_eslint(report: Path, project_dir: Path) -> list[Function]:
    data = json.loads(report.read_text(encoding="utf-8"))
    if not isinstance(data, list) or any(not isinstance(f, dict) or "messages" not in f for f in data):
        raise BadReport(f"{report}: eslint --format json writes a list of files with messages")
    unparsed = sorted({relative(f["filePath"], project_dir) for f in data if any(m.get("fatal") for m in f["messages"])})
    if unparsed:
        raise BadReport(f"eslint could not parse {', '.join(unparsed)}: nothing is judged until it does")
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


def read_jscpd(report: Path, project_dir: Path) -> list[Clone]:
    data = json.loads(report.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("duplicates"), list):
        raise BadReport(f"{report}: jscpd --reporters json writes an object with a duplicates list")
    entries = []
    for d in data["duplicates"]:
        a = relative(d["firstFile"]["name"], project_dir)
        b = relative(d["secondFile"]["name"], project_dir)
        entries.append((fingerprint(d["fragment"]), str(d["format"]), int(d["lines"]), a, b))
    return sorted(entries)


# --- ratchets ----------------------------------------------------------------------


def load_baseline(path: Path, width: int) -> list[list]:
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list) or any(not isinstance(e, list) or len(e) != width for e in data):
        raise BadReport(f"{path}: expected a list of {width}-field entries")
    return data


def write_baseline(path: Path, entries: list, freeze: str, what: str) -> int:
    if freeze == "init" and path.exists():
        print(f"ERROR: {path.name} already exists; --init-baseline never overwrites a baseline.", file=sys.stderr)
        return 2
    path.write_text(json.dumps([list(e) for e in entries], indent=2) + "\n", encoding="utf-8")
    print(f"{path.name}: {len(entries)} {what}(s) frozen.")
    return 0


def ratchet_complexity(current: list[Function], path: Path, freeze: str | None) -> int:
    if freeze:
        return write_baseline(path, current, freeze, "function above the threshold")
    baseline = {(str(file), str(label)): int(value) for file, label, value in load_baseline(path, 3)}
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


def ratchet_duplication(current: list[Clone], path: Path, freeze: str | None) -> int:
    if freeze:
        return write_baseline(path, current, freeze, "clone")
    known = Counter(str(e[0]) for e in load_baseline(path, 5))
    now = Counter(e[0] for e in current)
    new = [e for e in current if e[0] not in known]
    more = {fp: now[fp] - known[fp] for fp in sorted(now) if fp in known and now[fp] > known[fp]}
    fewer = sorted(fp for fp in known if now[fp] < known[fp])
    if fewer:
        print(f"{len(fewer)} baselined clone(s) found fewer times than {path.name} lists; remove the extra entries: {', '.join(fewer)}")
    if new or more:
        print(f"x duplication: {len(new)} clone(s) absent from {path.name}, {sum(more.values())} more cop(ies) of a known block:", file=sys.stderr)
        for fp, fmt, lines, a, b in new:
            print(f"  - {fp}  {fmt}, {lines} lines: {a} <> {b}  (new)", file=sys.stderr)
        for fp, extra in more.items():
            pairs = ", ".join(f"{a} <> {b}" for f, _, _, a, b in current if f == fp)
            print(f"  - {fp}  {extra} more pair(s) than the {known[fp]} known: {pairs}", file=sys.stderr)
        if not path.exists():
            print(f"To start from here, commit {path.name} with:", file=sys.stderr)
            print(json.dumps([list(e) for e in new], indent=2), file=sys.stderr)
        return 1
    print(f"OK: duplication, nothing new. {len(current)} known clone(s) tolerated by {path.name}.")
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
            clones = read_jscpd(report, project_dir)
            print(f"{len(clones)} clone(s) in the report.")
            return ratchet_duplication(clones, project_dir / DUPLICATION_BASELINE, args.freeze)
        reader = read_ruff if args.tool == "ruff" else read_eslint
        functions = reader(report, project_dir)
        print(f"{len(functions)} function(s) above the threshold in the report.")
        return ratchet_complexity(functions, project_dir / COMPLEXITY_BASELINE, args.freeze)
    except (BadReport, json.JSONDecodeError, KeyError, TypeError, ValueError, AttributeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
