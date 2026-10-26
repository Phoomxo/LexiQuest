"""Tests pinning the Voice API CUDA 12.8 dependency configuration."""

from __future__ import annotations

import tomllib
from pathlib import Path

from packaging.version import Version

PYPROJECT_PATH = Path(__file__).resolve().parent.parent / "pyproject.toml"
LOCKFILE_PATH = PYPROJECT_PATH.with_name("uv.lock")
EXPECTED_GPU_DEPS = [
    "omnivoice==0.2.1",
    "soundfile==0.14.0",
    "torch==2.11.0+cu128",
    "torchaudio==2.11.0+cu128",
]
EXPECTED_INDEX_NAME = "pytorch-cu128"
EXPECTED_INDEX_URL = "https://download.pytorch.org/whl/cu128"
EXPECTED_FASTAPI_PIN = "fastapi==0.140.0"
EXPECTED_HTTPX2_PIN = "httpx2==2.16.0"
SECURITY_FLOORS = {
    "accelerate": "1.15.0",
    "certifi": "2026.10.19",
    "cryptography": "50.0.0",
    "filelock": "4.2.1",
    "h2": "4.4.1",
    "httpcore2": "2.12.0",
    "httpx2": "2.12.0",
    "pyjwt": "2.15.0",
    "urllib3": "2.8.0",
}


def _load_pyproject() -> dict:
    with PYPROJECT_PATH.open("rb") as handle:
        return tomllib.load(handle)


def _load_locked_versions() -> dict[str, set[Version]]:
    with LOCKFILE_PATH.open("rb") as handle:
        packages = tomllib.load(handle)["package"]

    versions: dict[str, set[Version]] = {}
    for package in packages:
        versions.setdefault(package["name"], set()).add(Version(package["version"]))
    return versions


def test_gpu_dependency_group_pins_the_exact_supported_runtime() -> None:
    gpu_deps = _load_pyproject().get("dependency-groups", {}).get("gpu")

    assert gpu_deps == EXPECTED_GPU_DEPS


def test_project_dependencies_pin_exactly_one_fastapi_entry() -> None:
    config = _load_pyproject()
    project_deps = config.get("project", {}).get("dependencies", [])
    project_fastapi = [
        dependency
        for dependency in project_deps
        if dependency.lower().startswith("fastapi")
    ]
    grouped_fastapi = [
        dependency
        for group in config.get("dependency-groups", {}).values()
        for dependency in group
        if dependency.lower().startswith("fastapi")
    ]

    assert project_fastapi == [EXPECTED_FASTAPI_PIN]
    assert grouped_fastapi == []


def test_dev_http_client_uses_the_remediated_release() -> None:
    dev = _load_pyproject()["dependency-groups"]["dev"]

    assert [entry for entry in dev if entry.startswith("httpx2")] == [
        EXPECTED_HTTPX2_PIN
    ]


def test_a_single_explicit_pytorch_cu128_index_is_declared() -> None:
    indexes = _load_pyproject().get("tool", {}).get("uv", {}).get("index", [])
    pytorch_indexes = [
        index
        for index in indexes
        if isinstance(index, dict) and index.get("name", "").startswith("pytorch-")
    ]

    assert len(pytorch_indexes) == 1
    (index,) = pytorch_indexes
    assert index.get("name") == EXPECTED_INDEX_NAME
    assert index.get("url") == EXPECTED_INDEX_URL
    assert index.get("explicit") is True


def test_uv_sources_bind_torch_and_torchaudio_to_cu128() -> None:
    sources = _load_pyproject().get("tool", {}).get("uv", {}).get("sources", {})

    for package in ("torch", "torchaudio"):
        source = sources.get(package)
        assert isinstance(source, dict)
        assert source.get("index") == EXPECTED_INDEX_NAME


def test_no_cu132_pytorch_index_or_source_remains() -> None:
    tool_uv = _load_pyproject().get("tool", {}).get("uv", {})
    references: list[str] = []
    for index in tool_uv.get("index", []):
        if isinstance(index, dict):
            references.extend(
                value
                for key in ("name", "url")
                if isinstance((value := index.get(key)), str)
            )
    for source in tool_uv.get("sources", {}).values():
        if isinstance(source, dict) and isinstance(
            (target := source.get("index")), str
        ):
            references.append(target)

    assert not [reference for reference in references if "cu132" in reference]


def test_locked_remediated_dependencies_meet_security_floors() -> None:
    locked = _load_locked_versions()

    for package, floor in SECURITY_FLOORS.items():
        assert package in locked
        assert all(
            version >= Version(floor) for version in locked[package]
        ), f"{package} resolved below {floor}: {locked[package]}"


def test_omnivoice_demo_ui_is_excluded_from_the_api_runtime() -> None:
    config = _load_pyproject()
    metadata = config.get("tool", {}).get("uv", {}).get(
        "dependency-metadata", []
    )

    assert len(metadata) == 1
    (omnivoice,) = metadata
    assert omnivoice["name"] == "omnivoice"
    assert omnivoice["version"] == "0.2.1"
    requirements = set(omnivoice["requires-dist"])
    assert "gradio" not in requirements
    assert {
        "accelerate",
        "librosa",
        "numpy",
        "pydub",
        "soundfile",
        "tensorboardx",
        "torch>=2.4",
        "torchaudio>=2.4",
        "transformers>=5.3.0",
        "webdataset",
    } == requirements

    locked = _load_locked_versions()
    assert "gradio" not in locked
    assert "pillow" not in locked
