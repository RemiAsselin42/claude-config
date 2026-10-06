"""Tests for gates/python/check_quality.py.

Run:
    uv run --no-project --with grimp==3.14 --with pytest pytest tests/python -q

1. Reading the tools' reports: fixtures cut from real runs on papers-helper
   (tests/fixtures/quality/, 2026-10-06): ruff 0.16.10, eslint 9, jscpd 5.4.0.
2. The ratchets on those entries: new, grew, shrank, gone, init, update, blind spots.
3. The real tools on toy projects through uv and npx: ruff, eslint and jscpd all run on
   Windows, Linux and macOS, so these run everywhere uv and node are.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
from conftest import load_gate

cq = load_gate("check_quality")

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "quality"
PH = Path("/home/runner/work/papers-helper/papers-helper")
NPX = "npx.cmd" if sys.platform == "win32" else "npx"


# --- 1. reading ----------------------------------------------------------------


def test_ruff_report_gives_file_function_and_complexity() -> None:
    assert cq.read_ruff(FIXTURES / "ruff-c901.json", PH / "backend") == [
        ("app/graph/build.py", "merge_fuzzy_authors", 13),
        ("app/graph/build.py", "parse_authors", 12),
        ("app/ingestion.py", "_stream_upload", 21),
    ]


def test_eslint_report_keeps_only_complexity_and_numbers_anonymous_functions() -> None:
    assert cq.read_eslint(FIXTURES / "eslint-complexity.json", PH / "frontend") == [
        ("src/App.tsx", "Function 'renderMain'", 18),
        ("src/components/chat/ChatView.tsx", "Arrow function", 16),
        ("src/components/chat/ChatView.tsx", "Arrow function #2", 13),
        ("src/components/chat/ChatView.tsx", "Async function 'send'", 11),
        ("src/components/chat/ChatView.tsx", "Function 'ChatView'", 17),
    ]


def test_ordinals_follow_the_order_of_appearance_not_the_value() -> None:
    found = [("f.ts", "Arrow function", 11, 300), ("f.ts", "Arrow function", 40, 20), ("g.ts", "Arrow function", 12, 1)]
    assert cq.with_ordinals(found) == [("f.ts", "Arrow function", 40), ("f.ts", "Arrow function #2", 11), ("g.ts", "Arrow function", 12)]


def test_jscpd_report_gives_fingerprint_format_lines_and_files() -> None:
    entries = cq.read_jscpd(FIXTURES / "jscpd-report.json")
    assert {(e[1], e[2], e[3], e[4]) for e in entries} == {
        ("python", 9, "graph/builder.py", "routes/papers.py"),
        ("python", 8, "parsers/_epub.py", "parsers/_html.py"),
    }
    assert all(len(e[0]) == 12 for e in entries) and len({e[0] for e in entries}) == 2


def test_fingerprint_ignores_indentation_and_blank_lines_but_not_text() -> None:
    assert cq.fingerprint("  a = 1\n\n    b = 2\n") == cq.fingerprint("a = 1\nb = 2")
    assert cq.fingerprint("a = 1\nb = 2") != cq.fingerprint("a = 1\nb = 3")


def test_report_paths_become_relative_to_the_project(tmp_path: Path) -> None:
    assert cq.relative(str(tmp_path / "src" / "x.py"), tmp_path) == "src/x.py"
    assert cq.relative("C:\\elsewhere\\x.py", tmp_path).endswith("elsewhere/x.py")


# --- 2. ratchets -------------------------------------------------------------------


def run(project: Path, *args: str) -> int:
    return cq.main(["--project-dir", str(project), *args])


@pytest.fixture
def ruff_project(tmp_path: Path) -> Path:
    report = json.loads((FIXTURES / "ruff-c901.json").read_text(encoding="utf-8"))
    for d in report:
        d["filename"] = str(tmp_path / Path(d["filename"]).relative_to(PH / "backend"))
    (tmp_path / "ruff.json").write_text(json.dumps(report), encoding="utf-8")
    return tmp_path


def complexity_baseline(project: Path, entries: list[list]) -> None:
    (project / "complexity-baseline.json").write_text(json.dumps(entries), encoding="utf-8")


def test_no_baseline_is_red_and_prints_the_file_to_commit(ruff_project: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert run(ruff_project, "complexity", "--tool", "ruff", "--report", "ruff.json") == 1
    err = capsys.readouterr().err
    assert "3 new function(s)" in err
    assert json.loads(err.split("with:", 1)[1]) == [
        ["app/graph/build.py", "merge_fuzzy_authors", 13],
        ["app/graph/build.py", "parse_authors", 12],
        ["app/ingestion.py", "_stream_upload", 21],
    ]


def test_known_functions_are_tolerated(ruff_project: Path) -> None:
    complexity_baseline(ruff_project, [["app/graph/build.py", "merge_fuzzy_authors", 13], ["app/graph/build.py", "parse_authors", 12], ["app/ingestion.py", "_stream_upload", 21]])
    assert run(ruff_project, "complexity", "--tool", "ruff", "--report", "ruff.json") == 0


def test_a_known_function_that_grew_is_red(ruff_project: Path, capsys: pytest.CaptureFixture[str]) -> None:
    complexity_baseline(ruff_project, [["app/graph/build.py", "merge_fuzzy_authors", 13], ["app/graph/build.py", "parse_authors", 12], ["app/ingestion.py", "_stream_upload", 20]])
    assert run(ruff_project, "complexity", "--tool", "ruff", "--report", "ruff.json") == 1
    assert "_stream_upload = 21  (was 20)" in capsys.readouterr().err


def test_a_known_function_that_shrank_is_green_and_reported(ruff_project: Path, capsys: pytest.CaptureFixture[str]) -> None:
    complexity_baseline(ruff_project, [["app/graph/build.py", "merge_fuzzy_authors", 13], ["app/graph/build.py", "parse_authors", 12], ["app/ingestion.py", "_stream_upload", 25], ["app/old.py", "gone", 11]])
    assert run(ruff_project, "complexity", "--tool", "ruff", "--report", "ruff.json") == 0
    out = capsys.readouterr().out
    assert "_stream_upload went from 25 to 21" in out
    assert "gone is no longer above the threshold" in out


def test_init_and_update_baseline(ruff_project: Path) -> None:
    assert run(ruff_project, "complexity", "--tool", "ruff", "--report", "ruff.json", "--init-baseline") == 0
    path = ruff_project / "complexity-baseline.json"
    assert len(json.loads(path.read_text(encoding="utf-8"))) == 3
    assert run(ruff_project, "complexity", "--tool", "ruff", "--report", "ruff.json", "--init-baseline") == 2
    complexity_baseline(ruff_project, [])
    assert run(ruff_project, "complexity", "--tool", "ruff", "--report", "ruff.json", "--update-baseline") == 0
    assert len(json.loads(path.read_text(encoding="utf-8"))) == 3


def test_eslint_entries_ratchet_the_same_way(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    report = json.loads((FIXTURES / "eslint-complexity.json").read_text(encoding="utf-8"))
    for f in report:
        f["filePath"] = str(tmp_path / Path(f["filePath"]).relative_to(PH / "frontend"))
    (tmp_path / "eslint.json").write_text(json.dumps(report), encoding="utf-8")
    complexity_baseline(tmp_path, [["src/App.tsx", "Function 'renderMain'", 18], ["src/components/chat/ChatView.tsx", "Arrow function", 16], ["src/components/chat/ChatView.tsx", "Async function 'send'", 11], ["src/components/chat/ChatView.tsx", "Function 'ChatView'", 17]])
    assert run(tmp_path, "complexity", "--tool", "eslint", "--report", "eslint.json") == 1
    assert "Arrow function #2 = 13  (new)" in capsys.readouterr().err


def test_duplication_ratchet(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    shutil.copy(FIXTURES / "jscpd-report.json", tmp_path / "jscpd.json")
    assert run(tmp_path, "duplication", "--report", "jscpd.json") == 1
    err = capsys.readouterr().err
    assert "2 clone(s) absent" in err
    entries = json.loads(err.split("with:", 1)[1])
    (tmp_path / "duplication-baseline.json").write_text(json.dumps(entries[:1]), encoding="utf-8")
    assert run(tmp_path, "duplication", "--report", "jscpd.json") == 1
    assert "1 clone(s) absent" in capsys.readouterr().err
    (tmp_path / "duplication-baseline.json").write_text(json.dumps(entries + [["000000000000", "python", 5, "a.py", "b.py"]]), encoding="utf-8")
    assert run(tmp_path, "duplication", "--report", "jscpd.json") == 0
    assert "000000000000" in capsys.readouterr().out


def test_blind_spots(tmp_path: Path) -> None:
    assert run(tmp_path, "complexity", "--tool", "ruff", "--report", "absent.json") == 2
    (tmp_path / "bad.json").write_text('{"not": "a list"}', encoding="utf-8")
    assert run(tmp_path, "complexity", "--tool", "ruff", "--report", "bad.json") == 2
    assert run(tmp_path, "complexity", "--tool", "eslint", "--report", "bad.json") == 2
    (tmp_path / "list.json").write_text("[]", encoding="utf-8")
    assert run(tmp_path, "duplication", "--report", "list.json") == 2
    (tmp_path / "odd.json").write_text(json.dumps([{"code": "C901", "message": "something else", "filename": "x.py", "location": {"row": 1}}]), encoding="utf-8")
    assert run(tmp_path, "complexity", "--tool", "ruff", "--report", "odd.json") == 2


def test_no_violation_at_all_is_green(tmp_path: Path) -> None:
    (tmp_path / "ruff.json").write_text("[]", encoding="utf-8")
    assert run(tmp_path, "complexity", "--tool", "ruff", "--report", "ruff.json") == 0


# --- 3. the real tools ------------------------------------------------------------

RUFF = "ruff==0.16.10"
JSCPD = "jscpd@5.4.0"
ESLINT = "eslint@9"
COMPLEX_PY = "def f(x):\n" + "".join(f"    if x == {i}:\n        return {i}\n" for i in range(12)) + "    return -1\n"
COMPLEX_JS = "export function f(x) {\n" + "".join(f"  if (x === {i}) return {i};\n" for i in range(12)) + "  return -1;\n}\n"
BLOCK = "".join(f"const v{i} = compute({i}, {i + 1}, {i + 2});\n" for i in range(8))


def sh(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=600, check=False)


@pytest.mark.skipif(shutil.which("uv") is None, reason="uv is needed to run ruff")
def test_real_ruff_report_goes_through_the_gate(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    (tmp_path / "pkg").mkdir()
    (tmp_path / "pkg" / "deep.py").write_text(COMPLEX_PY, encoding="utf-8")
    cmd = ["uv", "run", "--no-project", "--python", "3.12", "--with", RUFF, "ruff", "check", "--select", "C901",
           "--config", "lint.mccabe.max-complexity=10", "--output-format", "json", "--isolated", "--exit-zero", "pkg"]
    proc = sh(cmd, tmp_path)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    (tmp_path / "ruff.json").write_text(proc.stdout, encoding="utf-8")
    assert cq.read_ruff(tmp_path / "ruff.json", tmp_path) == [("pkg/deep.py", "f", 13)]
    assert run(tmp_path, "complexity", "--tool", "ruff", "--report", "ruff.json") == 1
    assert run(tmp_path, "complexity", "--tool", "ruff", "--report", "ruff.json", "--init-baseline") == 0
    assert run(tmp_path, "complexity", "--tool", "ruff", "--report", "ruff.json") == 0
    capsys.readouterr()


@pytest.mark.skipif(shutil.which(NPX) is None, reason="node is needed to run eslint")
def test_real_eslint_report_goes_through_the_gate(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "deep.js").write_text(COMPLEX_JS, encoding="utf-8")
    cmd = [NPX, "--yes", "-p", ESLINT, "eslint", "--no-config-lookup", "--rule", "complexity: [2, 10]", "--format", "json", "src"]
    proc = sh(cmd, tmp_path)
    assert proc.stdout.startswith("["), proc.stdout + proc.stderr
    (tmp_path / "eslint.json").write_text(proc.stdout, encoding="utf-8")
    assert cq.read_eslint(tmp_path / "eslint.json", tmp_path) == [("src/deep.js", "Function 'f'", 13)]
    assert run(tmp_path, "complexity", "--tool", "eslint", "--report", "eslint.json") == 1
    assert run(tmp_path, "complexity", "--tool", "eslint", "--report", "eslint.json", "--init-baseline") == 0
    assert run(tmp_path, "complexity", "--tool", "eslint", "--report", "eslint.json") == 0
    capsys.readouterr()


@pytest.mark.skipif(shutil.which(NPX) is None, reason="node is needed to run jscpd")
def test_real_jscpd_report_goes_through_the_gate(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "a.ts").write_text("export function a() {\n" + BLOCK + "}\n", encoding="utf-8")
    (tmp_path / "src" / "b.ts").write_text("export function b() {\n" + BLOCK + "}\n", encoding="utf-8")
    cmd = [NPX, "--yes", JSCPD, "src", "--reporters", "json", "--output", ".jscpd", "--silent"]
    proc = sh(cmd, tmp_path)
    report = tmp_path / ".jscpd" / "jscpd-report.json"
    assert report.exists(), proc.stdout + proc.stderr
    entries = cq.read_jscpd(report)
    assert len(entries) == 1 and entries[0][1] == "typescript" and {entries[0][3], entries[0][4]} == {"a.ts", "b.ts"}, entries
    assert run(tmp_path, "duplication", "--report", str(report)) == 1
    assert run(tmp_path, "duplication", "--report", str(report), "--init-baseline") == 0
    assert run(tmp_path, "duplication", "--report", str(report)) == 0
    # The same clone, moved down in one file: same fingerprint, still tolerated.
    (tmp_path / "src" / "b.ts").write_text("const pad = 1;\n\nexport function b() {\n" + BLOCK + "}\n", encoding="utf-8")
    shutil.rmtree(tmp_path / ".jscpd")
    sh(cmd, tmp_path)
    assert run(tmp_path, "duplication", "--report", str(report)) == 0
    capsys.readouterr()
