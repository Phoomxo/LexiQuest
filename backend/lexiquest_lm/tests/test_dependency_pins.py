"""Dependency pin contracts for the LexiQuest-LM environment."""

from __future__ import annotations

import tomllib
from pathlib import Path

_PYPROJECT = Path(__file__).resolve().parent.parent / "pyproject.toml"
_EXPECTED_TQDM = "tqdm==4.69.1"
_EXPECTED_TORCH = "torch==2.13.0+cu132"
_INDEX_NAME = "pytorch-cu132"
_INDEX_URL = "https://download.pytorch.org/whl/cu132"


def _load_pyproject() -> dict:
    with _PYPROJECT.open("rb") as handle:
        return tomllib.load(handle)


def _matching(entries: list[str], prefix: str) -> list[str]:
    return [entry for entry in entries if entry.lower().startswith(prefix)]


def test_project_dependencies_pin_tqdm_once() -> None:
    data = _load_pyproject()

    assert _matching(data["project"]["dependencies"], "tqdm") == [
        _EXPECTED_TQDM
    ]


def test_training_torch_cuda_contract_is_unchanged() -> None:
    data = _load_pyproject()
    groups = data["dependency-groups"]
    index = next(
        entry
        for entry in data["tool"]["uv"]["index"]
        if entry.get("name") == _INDEX_NAME
    )

    assert _matching(groups["train"], "torch") == [_EXPECTED_TORCH]
    assert index.get("url") == _INDEX_URL
    assert data["tool"]["uv"]["sources"]["torch"]["index"] == _INDEX_NAME
    assert all(
        not _matching(entries, "torch")
        for name, entries in groups.items()
        if name != "train"
    )


def test_dependency_groups_do_not_redeclare_tqdm() -> None:
    groups = _load_pyproject()["dependency-groups"]

    assert all(not _matching(entries, "tqdm") for entries in groups.values())
