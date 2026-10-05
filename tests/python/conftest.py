"""Shared by the gate tests: load a gate script from gates/python by name, the way CI
runs it (a file at a pinned tag, not an installed package)."""

from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType

GATES = Path(__file__).resolve().parents[2] / "gates" / "python"


def load_gate(name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, GATES / f"{name}.py")
    assert spec and spec.loader, name
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
