"""Shared pytest fixtures for the lexiquest_lm dataset pipeline tests."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

# Make the dataset scripts importable as modules. They live alongside this
# tests dir's parent (backend/lexiquest_lm/dataset/) and are not part of the
# installed package, so we add that directory to sys.path for the test run.
_BACKEND_ROOT = Path(__file__).resolve().parent.parent
_DATASET_DIR = _BACKEND_ROOT / "dataset"
if str(_DATASET_DIR) not in sys.path:
    sys.path.insert(0, str(_DATASET_DIR))
if str(_BACKEND_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT / "src"))


@pytest.fixture
def tmp_jsonl(tmp_path: Path) -> Path:
    """Return a path for a throwaway JSONL file inside the test's tmp dir."""

    return tmp_path / "data.jsonl"


def write_jsonl_rows(path: Path, rows: list[dict[str, object]]) -> None:
    """Helper: write a list of dicts as JSONL (used by sample-input fixtures)."""

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False))
            handle.write("\n")
