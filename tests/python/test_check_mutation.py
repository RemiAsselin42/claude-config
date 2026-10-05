"""Tests for gates/python/check_mutation.py.

Run:
    uv run --no-project --with grimp==3.14 --with pytest pytest tests/python -q

1. Reading mutmut's .meta files: the status table (against mutmut's own, through uv),
   function keys, not-killed, blind spots.
2. main() end to end on written .meta files: exit codes 0 / 1 / 2, the baseline of
   [name, function hash] pairs, a function that changed since the baseline.
3. The real tool: `mutmut run` on a toy package through uv, the gate on its output,
   then an edit to the untested function and a second run. mutmut refuses native
   Windows, so that one runs on Linux and macOS (CI); the table comparison only
   imports mutmut and runs everywhere uv is.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
from conftest import load_gate

cm = load_gate("check_mutation")

MUTMUT = "mutmut==3.8.0"
UV = ["uv", "run", "--no-project", "--python", "3.12", "--with", MUTMUT, "--with", "pytest"]


def write_meta(project: Path, source: str, exit_codes: dict[str, int | None], hashes: dict[str, str] | None = None) -> None:
    """One mutants/<source>.meta the way mutmut 3.8 saves it (SourceFileMutationData.save)."""
    if hashes is None:
        hashes = {cm.function_key(name): "hash-" + cm.function_key(name) for name in exit_codes}
    meta = project / "mutants" / (source + ".meta")
    meta.parent.mkdir(parents=True, exist_ok=True)
    meta.write_text(
        json.dumps(
            {
                "exit_code_by_key": exit_codes,
                "hash_by_function_name": hashes,
                "type_check_error_by_key": {},
                "durations_by_key": {},
                "estimated_durations_by_key": {},
            },
            indent=4,
        ),
        encoding="utf-8",
    )


# --- 1. reading ----------------------------------------------------------------


@pytest.mark.skipif(shutil.which("uv") is None, reason="uv is needed to import mutmut")
def test_status_table_equals_mutmuts() -> None:
    """The vendored table is mutmut's, entry for entry (importing mutmut.stats works on Windows too)."""
    code = "import json; from mutmut.stats import status_by_exit_code as s; print(json.dumps(list(s.items())))"
    out = subprocess.run([*UV, "python", "-c", code], capture_output=True, text=True, check=True, timeout=600).stdout
    theirs = {k: v for k, v in json.loads(out.strip().splitlines()[-1])}
    assert cm.STATUS_BY_EXIT_CODE == theirs
    assert cm.status(99) == "suspicious"  # their defaultdict's default


def test_function_key() -> None:
    assert cm.function_key("pkg.calc.x_add__mutmut_3") == "x_add"
    assert cm.function_key("app.parsers._bibtex.x_Parser__parse__mutmut_12") == "x_Parser__parse"


def test_results_carry_status_and_function_hash_from_every_meta_file(tmp_path: Path) -> None:
    write_meta(tmp_path, "pkg/a.py", {"pkg.a.x_f__mutmut_1": 1}, {"x_f": "h1"})
    write_meta(tmp_path, "pkg/sub/b.py", {"pkg.sub.b.x_g__mutmut_1": 0}, {"x_g": "h2"})
    assert cm.read_results(tmp_path) == {"pkg.a.x_f__mutmut_1": ("killed", "h1"), "pkg.sub.b.x_g__mutmut_1": ("survived", "h2")}


def test_not_killed_is_survived_plus_no_tests_only() -> None:
    results = {
        "s": ("survived", "h"),
        "n": ("no tests", "h"),
        "k": ("killed", "h"),
        "c": ("caught by type check", "h"),
        "t": ("timeout", "h"),
        "u": ("suspicious", "h"),
        "p": ("skipped", "h"),
        "g": ("segfault", "h"),
    }
    assert cm.not_killed(results) == [("n", "h"), ("s", "h")]


def test_blind_spots() -> None:
    assert cm.blind_spot({}) is not None
    assert "did not complete" in (cm.blind_spot({"a": ("killed", "h"), "b": ("not checked", "h")}) or "")
    assert "did not complete" in (cm.blind_spot({"a": ("killed", "h"), "b": ("check was interrupted by user", "h")}) or "")
    assert "decisive" in (cm.blind_spot({"a": ("timeout", "h"), "b": ("suspicious", "h"), "c": ("skipped", "h")}) or "")
    assert cm.blind_spot({"a": ("caught by type check", "h"), "b": ("timeout", "h")}) is None
    assert cm.blind_spot({"a": ("killed", "h"), "b": ("survived", "h")}) is None


# --- 2. main() end to end ----------------------------------------------------------

POS1 = "pkg.calc.x_is_positive__mutmut_1"
POS2 = "pkg.calc.x_is_positive__mutmut_2"
HASHES = {"x_add": "hash-add", "x_is_positive": "hash-pos"}


@pytest.fixture
def project(tmp_path: Path) -> Path:
    write_meta(
        tmp_path,
        "pkg/calc.py",
        {
            "pkg.calc.x_add__mutmut_1": 1,
            "pkg.calc.x_add__mutmut_2": 3,
            "pkg.calc.x_add__mutmut_3": 37,
            POS1: 0,
            POS2: 33,
            "pkg.calc.x_is_positive__mutmut_3": 36,
        },
        HASHES,
    )
    return tmp_path


def run(project: Path, *extra: str) -> int:
    return cm.main(["--project-dir", str(project), *extra])


def baseline(project: Path, entries: list[list[str]]) -> None:
    (project / "mutation-baseline.json").write_text(json.dumps(entries), encoding="utf-8")


def test_no_baseline_is_red_and_prints_the_file_to_commit(project: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert run(project) == 1
    err = capsys.readouterr().err
    assert "x_is_positive__mutmut_3" not in err  # a timeout is noise, not a hole
    assert "x_add" not in err  # killed, and caught by the type checker, are kills
    assert json.loads(err.split("with:", 1)[1]) == [[POS1, "hash-pos"], [POS2, "hash-pos"]]


def test_baselined_not_killed_mutants_are_tolerated(project: Path) -> None:
    baseline(project, [[POS1, "hash-pos"], [POS2, "hash-pos"]])
    assert run(project) == 0


def test_a_new_not_killed_mutant_is_red(project: Path, capsys: pytest.CaptureFixture[str]) -> None:
    baseline(project, [[POS1, "hash-pos"]])
    assert run(project) == 1
    err = capsys.readouterr().err
    assert "1 not-killed mutant(s) absent from mutation-baseline.json" in err
    assert f"{POS2}  (new)" in err


def test_a_baselined_name_whose_function_changed_is_red(project: Path, capsys: pytest.CaptureFixture[str]) -> None:
    """Names are positional: after an edit, the old #1 may be a different mutation."""
    baseline(project, [[POS1, "old-hash"], [POS2, "old-hash"]])
    assert run(project) == 1
    captured = capsys.readouterr()
    assert f"{POS1}  (its function changed since the baseline: re-examine)" in captured.err
    assert "2 baselined entry(ies) no longer current" in captured.out


def test_a_baselined_mutant_now_killed_is_reported_not_failed(project: Path, capsys: pytest.CaptureFixture[str]) -> None:
    baseline(project, [["pkg.calc.x_add__mutmut_1", "hash-add"], [POS1, "hash-pos"], [POS2, "hash-pos"]])
    assert run(project) == 0
    assert "pkg.calc.x_add__mutmut_1" in capsys.readouterr().out


def test_init_baseline_creates_pairs_and_never_overwrites(project: Path) -> None:
    assert run(project, "--init-baseline") == 0
    path = project / "mutation-baseline.json"
    assert json.loads(path.read_text(encoding="utf-8")) == [[POS1, "hash-pos"], [POS2, "hash-pos"]]
    before = path.read_text(encoding="utf-8")
    assert run(project, "--init-baseline") == 2
    assert path.read_text(encoding="utf-8") == before
    assert run(project) == 0


def test_update_baseline_rewrites(project: Path) -> None:
    baseline(project, [])
    assert run(project, "--update-baseline") == 0
    assert len(json.loads((project / "mutation-baseline.json").read_text(encoding="utf-8"))) == 2


def test_no_meta_is_a_blind_spot(tmp_path: Path) -> None:
    assert run(tmp_path) == 2


def test_zero_mutants_is_a_blind_spot(tmp_path: Path) -> None:
    write_meta(tmp_path, "pkg/calc.py", {})
    assert run(tmp_path) == 2


def test_an_incomplete_run_is_a_blind_spot(tmp_path: Path) -> None:
    write_meta(tmp_path, "pkg/calc.py", {"pkg.calc.x_add__mutmut_1": 1, "pkg.calc.x_add__mutmut_2": None})
    assert run(tmp_path) == 2
    write_meta(tmp_path, "pkg/calc.py", {"pkg.calc.x_add__mutmut_1": 1, "pkg.calc.x_add__mutmut_2": 2})
    assert run(tmp_path) == 2


def test_all_noise_is_a_blind_spot_not_a_green(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    """A loaded runner that times out on every mutant must not pass as 'no new survivor'."""
    write_meta(tmp_path, "pkg/calc.py", {"pkg.calc.x_add__mutmut_1": 36, "pkg.calc.x_add__mutmut_2": 35, "pkg.calc.x_add__mutmut_3": -9})
    assert run(tmp_path) == 2
    assert "decisive" in capsys.readouterr().err


# --- 3. the real tool ---------------------------------------------------------------

CALC = "def add(a, b):\n    return a + b\n\n\ndef is_positive(x):\n    return x > 0\n"
CALC_EDITED = "def add(a, b):\n    return a + b\n\n\ndef is_positive(x):\n    y = x\n    return y > 0\n"


def mutmut_run(project: Path) -> None:
    proc = subprocess.run([*UV, "mutmut", "run"], cwd=project, capture_output=True, text=True, timeout=600, check=False)
    assert proc.returncode == 0, proc.stdout + proc.stderr


@pytest.mark.skipif(sys.platform == "win32", reason="mutmut refuses to run on native Windows")
@pytest.mark.skipif(shutil.which("uv") is None, reason="uv is needed to run mutmut")
def test_real_mutmut_output_goes_through_the_gate(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    """add() is tested, is_positive() is not: its mutants are not killed, add's are."""
    (tmp_path / "pkg").mkdir()
    (tmp_path / "pkg" / "__init__.py").write_text("", encoding="utf-8")
    (tmp_path / "pkg" / "calc.py").write_text(CALC, encoding="utf-8")
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
    mutmut_run(tmp_path)

    results = cm.read_results(tmp_path)
    assert results
    statuses = {st for st, _ in results.values()}
    assert "killed" in statuses, results
    assert statuses & set(cm.NOT_KILLED), results
    assert all(name.startswith("pkg.calc.") for name in results), results
    assert all(st in {"killed", "survived", "no tests"} for st in statuses), results
    assert all(h for _, h in results.values()), results  # every mutant carries its function's hash

    assert run(tmp_path) == 1
    err = capsys.readouterr().err
    assert "is_positive" in err and "x_add" not in err
    assert run(tmp_path, "--init-baseline") == 0
    assert run(tmp_path) == 0

    # The untested function is edited: mutmut renumbers its mutants and rehashes it,
    # the baselined names are no longer tolerated.
    (tmp_path / "pkg" / "calc.py").write_text(CALC_EDITED, encoding="utf-8")
    mutmut_run(tmp_path)
    assert run(tmp_path) == 1
    assert "its function changed since the baseline" in capsys.readouterr().err
