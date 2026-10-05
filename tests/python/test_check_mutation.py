"""Tests for gates/python/check_mutation.py.

Run:
    uv run --no-project --with grimp==3.14 --with pytest pytest tests/python -q

1. Reading mutmut's .meta files: the status table, not-killed, blind spots.
2. main() end to end on written .meta files: exit codes 0 / 1 / 2 and the baseline.
3. The real tool: `mutmut run` on a toy package through uv, then the gate on its
   output. mutmut refuses native Windows, so this one runs on Linux and macOS (CI).
"""

from __future__ import annotations

import importlib.util
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

_SCRIPT = Path(__file__).resolve().parents[2] / "gates" / "python" / "check_mutation.py"
_spec = importlib.util.spec_from_file_location("check_mutation", _SCRIPT)
assert _spec and _spec.loader
cm = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cm)


def write_meta(project: Path, source: str, exit_codes: dict[str, int | None]) -> None:
    """One mutants/<source>.meta the way mutmut 3.8 saves it (SourceFileMutationData.save)."""
    meta = project / "mutants" / (source + ".meta")
    meta.parent.mkdir(parents=True, exist_ok=True)
    meta.write_text(
        json.dumps(
            {
                "exit_code_by_key": exit_codes,
                "hash_by_function_name": {},
                "type_check_error_by_key": {},
                "durations_by_key": {},
                "estimated_durations_by_key": {},
            },
            indent=4,
        ),
        encoding="utf-8",
    )


# --- 1. reading ----------------------------------------------------------------


def test_status_table_matches_mutmut() -> None:
    assert cm.status(0) == "survived"
    assert cm.status(1) == "killed"
    assert cm.status(3) == "killed"
    assert cm.status(33) == "no tests"
    assert cm.status(36) == "timeout"
    assert cm.status(None) == "not checked"
    assert cm.status(99) == "suspicious"


def test_results_are_read_from_every_meta_file(tmp_path: Path) -> None:
    write_meta(tmp_path, "pkg/a.py", {"pkg.a.x_f__mutmut_1": 1})
    write_meta(tmp_path, "pkg/sub/b.py", {"pkg.sub.b.x_g__mutmut_1": 0})
    assert cm.read_results(tmp_path) == {"pkg.a.x_f__mutmut_1": "killed", "pkg.sub.b.x_g__mutmut_1": "survived"}


def test_not_killed_is_survived_plus_no_tests_only() -> None:
    results = {"s": "survived", "n": "no tests", "k": "killed", "t": "timeout", "u": "suspicious", "p": "skipped"}
    assert cm.not_killed(results) == ["n", "s"]


def test_blind_spots() -> None:
    assert cm.blind_spot({}) is not None
    assert "interrupted" in (cm.blind_spot({"a": "killed", "b": "not checked"}) or "")
    assert cm.blind_spot({"a": "killed", "b": "survived"}) is None


# --- 2. main() end to end ----------------------------------------------------------


@pytest.fixture
def project(tmp_path: Path) -> Path:
    write_meta(
        tmp_path,
        "pkg/calc.py",
        {
            "pkg.calc.x_add__mutmut_1": 1,
            "pkg.calc.x_add__mutmut_2": 3,
            "pkg.calc.x_is_positive__mutmut_1": 0,
            "pkg.calc.x_is_positive__mutmut_2": 33,
            "pkg.calc.x_is_positive__mutmut_3": 36,
        },
    )
    return tmp_path


def run(project: Path, *extra: str) -> int:
    return cm.main(["--project-dir", str(project), *extra])


def test_no_baseline_is_red_and_prints_the_file_to_commit(project: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert run(project) == 1
    err = capsys.readouterr().err
    assert "pkg.calc.x_is_positive__mutmut_1" in err and "pkg.calc.x_is_positive__mutmut_2" in err
    assert "x_is_positive__mutmut_3" not in err  # a timeout is noise, not a hole
    assert "x_add" not in err
    assert json.loads(err.split("with:", 1)[1]) == ["pkg.calc.x_is_positive__mutmut_1", "pkg.calc.x_is_positive__mutmut_2"]


def test_baselined_not_killed_mutants_are_tolerated(project: Path) -> None:
    (project / "mutation-baseline.json").write_text(
        json.dumps(["pkg.calc.x_is_positive__mutmut_1", "pkg.calc.x_is_positive__mutmut_2"]), encoding="utf-8"
    )
    assert run(project) == 0


def test_a_new_not_killed_mutant_is_red(project: Path, capsys: pytest.CaptureFixture[str]) -> None:
    (project / "mutation-baseline.json").write_text(json.dumps(["pkg.calc.x_is_positive__mutmut_1"]), encoding="utf-8")
    assert run(project) == 1
    err = capsys.readouterr().err
    assert "1 not-killed mutant(s) absent from mutation-baseline.json" in err
    assert "pkg.calc.x_is_positive__mutmut_2" in err


def test_a_baselined_mutant_now_killed_is_reported_not_failed(project: Path, capsys: pytest.CaptureFixture[str]) -> None:
    (project / "mutation-baseline.json").write_text(
        json.dumps(["pkg.calc.x_add__mutmut_1", "pkg.calc.x_is_positive__mutmut_1", "pkg.calc.x_is_positive__mutmut_2"]),
        encoding="utf-8",
    )
    assert run(project) == 0
    assert "pkg.calc.x_add__mutmut_1" in capsys.readouterr().out


def test_init_baseline_creates_sorted_and_never_overwrites(project: Path) -> None:
    assert run(project, "--init-baseline") == 0
    baseline = project / "mutation-baseline.json"
    assert json.loads(baseline.read_text(encoding="utf-8")) == [
        "pkg.calc.x_is_positive__mutmut_1",
        "pkg.calc.x_is_positive__mutmut_2",
    ]
    before = baseline.read_text(encoding="utf-8")
    assert run(project, "--init-baseline") == 2
    assert baseline.read_text(encoding="utf-8") == before
    assert run(project) == 0


def test_update_baseline_rewrites(project: Path) -> None:
    (project / "mutation-baseline.json").write_text("[]", encoding="utf-8")
    assert run(project, "--update-baseline") == 0
    assert len(json.loads((project / "mutation-baseline.json").read_text(encoding="utf-8"))) == 2


def test_no_meta_is_a_blind_spot(tmp_path: Path) -> None:
    assert run(tmp_path) == 2


def test_zero_mutants_is_a_blind_spot(tmp_path: Path) -> None:
    write_meta(tmp_path, "pkg/calc.py", {})
    assert run(tmp_path) == 2


def test_an_interrupted_run_is_a_blind_spot(tmp_path: Path) -> None:
    write_meta(tmp_path, "pkg/calc.py", {"pkg.calc.x_add__mutmut_1": 1, "pkg.calc.x_add__mutmut_2": None})
    assert run(tmp_path) == 2


# --- 3. the real tool ---------------------------------------------------------------

MUTMUT = "mutmut==3.8.0"


@pytest.mark.skipif(sys.platform == "win32", reason="mutmut refuses to run on native Windows")
@pytest.mark.skipif(shutil.which("uv") is None, reason="uv is needed to run mutmut")
def test_real_mutmut_output_goes_through_the_gate(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    """add() is tested, is_positive() is not: its mutants are not killed, add's are."""
    (tmp_path / "pkg").mkdir()
    (tmp_path / "pkg" / "__init__.py").write_text("", encoding="utf-8")
    (tmp_path / "pkg" / "calc.py").write_text(
        "def add(a, b):\n    return a + b\n\n\ndef is_positive(x):\n    return x > 0\n", encoding="utf-8"
    )
    (tmp_path / "tests").mkdir()
    (tmp_path / "tests" / "test_calc.py").write_text(
        "from pkg.calc import add\n\n\ndef test_add():\n    assert add(1, 2) == 3\n    assert add(-1, 1) == 0\n",
        encoding="utf-8",
    )
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "toy"\nversion = "0"\n\n[tool.mutmut]\nsource_paths = ["pkg"]\n'
        'pytest_add_cli_args_test_selection = ["tests"]\n',
        encoding="utf-8",
    )
    run_cmd = ["uv", "run", "--no-project", "--python", "3.12", "--with", MUTMUT, "--with", "pytest", "mutmut", "run"]
    proc = subprocess.run(run_cmd, cwd=tmp_path, capture_output=True, text=True, timeout=600, check=False)
    assert (tmp_path / "mutants").is_dir(), proc.stdout + proc.stderr

    results = cm.read_results(tmp_path)
    assert results, proc.stdout + proc.stderr
    statuses = set(results.values())
    assert "killed" in statuses, results
    assert statuses & set(cm.NOT_KILLED), results
    assert all(name.startswith("pkg.calc.") for name in results), results
    assert all(st in {"killed", "survived", "no tests"} for st in statuses), results

    assert run(tmp_path) == 1
    err = capsys.readouterr().err
    assert "is_positive" in err and "x_add" not in err
    assert run(tmp_path, "--init-baseline") == 0
    assert run(tmp_path) == 0
