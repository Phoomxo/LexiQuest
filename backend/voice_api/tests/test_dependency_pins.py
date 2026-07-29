"""Tests pinning the Voice API CUDA 13.2 dependency configuration."""

from __future__ import annotations

import tomllib
from pathlib import Path

PYPROJECT_PATH = Path(__file__).resolve().parent.parent / "pyproject.toml"
EXPECTED_GPU_DEPS = [
    "omnivoice==0.2.1",
    "soundfile==0.14.0",
    "torch==2.13.0+cu132",
    "torchaudio==2.11.0",
]
EXPECTED_INDEX_NAME = "pytorch-cu132"
EXPECTED_INDEX_URL = "https://download.pytorch.org/whl/cu132"
EXPECTED_FASTAPI_PIN = "fastapi==0.140.0"


def _load_pyproject() -> dict:
    with PYPROJECT_PATH.open("rb") as handle:
        return tomllib.load(handle)


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


def test_a_single_explicit_pytorch_cu132_index_is_declared() -> None:
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


def test_uv_sources_bind_only_torch_to_cu132() -> None:
    sources = _load_pyproject().get("tool", {}).get("uv", {}).get("sources", {})

    torch_source = sources.get("torch")
    assert isinstance(torch_source, dict)
    assert torch_source.get("index") == EXPECTED_INDEX_NAME
    assert "torchaudio" not in sources


def test_no_cu128_pytorch_index_or_source_remains() -> None:
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

    assert not [reference for reference in references if "cu128" in reference]
