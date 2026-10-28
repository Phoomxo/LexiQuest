"""Dependency pin contracts for the AI API."""

from __future__ import annotations

import tomllib
from pathlib import Path

_PYPROJECT = Path(__file__).resolve().parent.parent / "pyproject.toml"
_EXPECTED_FASTAPI = "fastapi==0.140.0"


def _load_pyproject() -> dict:
    with _PYPROJECT.open("rb") as handle:
        return tomllib.load(handle)


def test_project_dependencies_pin_fastapi_once() -> None:
    data = _load_pyproject()
    direct = data.get("project", {}).get("dependencies", [])
    fastapi = [entry for entry in direct if entry.lower().startswith("fastapi")]

    assert fastapi == [_EXPECTED_FASTAPI]


def test_dependency_groups_do_not_redeclare_fastapi() -> None:
    groups = _load_pyproject().get("dependency-groups", {})
    elsewhere = [
        entry
        for entries in groups.values()
        for entry in entries
        if entry.lower().startswith("fastapi")
    ]

    assert elsewhere == []
