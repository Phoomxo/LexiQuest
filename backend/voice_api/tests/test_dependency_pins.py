"""Tests pinning the Voice API CUDA 12.8 dependency configuration."""

from __future__ import annotations

import tomllib
from pathlib import Path

PYPROJECT_PATH = Path(__file__).resolve().parent.parent / "pyproject.toml"
EXPECTED_GPU_DEPS = [
    "omnivoice==0.2.1",
    "soundfile==0.13.1",
    "torch==2.8.0+cu128",
    "torchaudio==2.8.0+cu128",
]
EXPECTED_INDEX_NAME = "pytorch-cu128"
EXPECTED_INDEX_URL = "https://download.pytorch.org/whl/cu128"


def _load_pyproject() -> dict:
    with PYPROJECT_PATH.open("rb") as handle:
        return tomllib.load(handle)


def test_gpu_dependency_group_pins_the_exact_supported_runtime() -> None:
    gpu_deps = _load_pyproject().get("dependency-groups", {}).get("gpu")

    assert gpu_deps == EXPECTED_GPU_DEPS


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
