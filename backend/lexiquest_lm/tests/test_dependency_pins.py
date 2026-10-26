"""Dependency pin contracts for the LexiQuest-LM environment."""

from __future__ import annotations

import tomllib
from pathlib import Path

from packaging.version import Version

_PYPROJECT = Path(__file__).resolve().parent.parent / "pyproject.toml"
_LOCKFILE = _PYPROJECT.with_name("uv.lock")
_HF_REQUIREMENTS = _PYPROJECT.parent / "deploy" / "hf_space" / "requirements.txt"
_EXPECTED_TQDM = "tqdm==4.69.1"
_EXPECTED_TORCH = "torch==2.13.0+cu132"
_EXPECTED_TRAINING_SECURITY_PINS = {
    "accelerate==1.15.0",
    "datasets==5.0.1",
}
_EXPECTED_HF_SECURITY_PINS = {
    "accelerate==1.15.0",
    "anyio==4.15.1",
    "certifi==2026.10.23",
}
_SECURITY_FLOORS = {
    "accelerate": "1.15.0",
    "aiohttp": "3.14.4",
    "certifi": "2026.10.19",
    "datasets": "5.0.1",
    "filelock": "4.2.1",
    "fsspec": "2026.6.0",
    "multidict": "6.9.1",
    "setuptools": "84.1.0",
    "urllib3": "2.8.0",
}
_INDEX_NAME = "pytorch-cu132"
_INDEX_URL = "https://download.pytorch.org/whl/cu132"


def _load_pyproject() -> dict:
    with _PYPROJECT.open("rb") as handle:
        return tomllib.load(handle)


def _load_locked_versions() -> dict[str, set[Version]]:
    with _LOCKFILE.open("rb") as handle:
        packages = tomllib.load(handle)["package"]

    versions: dict[str, set[Version]] = {}
    for package in packages:
        versions.setdefault(package["name"], set()).add(Version(package["version"]))
    return versions


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


def test_training_dependencies_use_remediated_releases() -> None:
    training = set(_load_pyproject()["dependency-groups"]["train"])

    assert _EXPECTED_TRAINING_SECURITY_PINS <= training


def test_hf_space_pins_security_sensitive_transitive_dependencies() -> None:
    requirements = {
        line.strip()
        for line in _HF_REQUIREMENTS.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }

    assert _EXPECTED_HF_SECURITY_PINS <= requirements


def test_locked_dependencies_meet_security_floors() -> None:
    locked = _load_locked_versions()

    for package, floor in _SECURITY_FLOORS.items():
        assert package in locked
        assert all(
            version >= Version(floor) for version in locked[package]
        ), f"{package} resolved below {floor}: {locked[package]}"
