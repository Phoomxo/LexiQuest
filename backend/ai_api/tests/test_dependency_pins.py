"""Dependency pin contracts for the AI API."""

from __future__ import annotations

import tomllib
from pathlib import Path

from packaging.version import Version

_PYPROJECT = Path(__file__).resolve().parent.parent / "pyproject.toml"
_LOCKFILE = _PYPROJECT.with_name("uv.lock")
_EXPECTED_FASTAPI = "fastapi==0.140.0"
_EXPECTED_HTTPX2 = "httpx2==2.16.0"
_EXPECTED_ACCOUNT_EXPORT_CRYPTO = {
    "google-cloud-kms==3.18.0",
    "google-crc32c==1.8.0",
}
_SECURITY_FLOORS = {
    "certifi": "2026.10.19",
    "cryptography": "50.0.0",
    "h2": "4.4.1",
    "httpcore2": "2.12.0",
    "httpx2": "2.12.0",
    "msgpack": "1.2.3",
    "pyjwt": "2.15.0",
    "urllib3": "2.8.0",
}


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


def test_account_export_crypto_dependencies_are_exactly_pinned() -> None:
    direct = set(
        _load_pyproject().get("project", {}).get("dependencies", [])
    )

    assert _EXPECTED_ACCOUNT_EXPORT_CRYPTO <= direct


def test_dev_http_client_uses_the_remediated_release() -> None:
    dev = _load_pyproject()["dependency-groups"]["dev"]

    assert [entry for entry in dev if entry.startswith("httpx2")] == [
        _EXPECTED_HTTPX2
    ]


def test_locked_dependencies_meet_security_floors() -> None:
    locked = _load_locked_versions()

    for package, floor in _SECURITY_FLOORS.items():
        assert package in locked
        assert all(
            version >= Version(floor) for version in locked[package]
        ), f"{package} resolved below {floor}: {locked[package]}"
