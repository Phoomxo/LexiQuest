"""Tests for merge_and_format.py.

The merge must:
- normalise heterogeneous raw rows to the trainer's instruction shape,
- dedupe on (prompt, response),
- stratify splits by ``kind`` so each split sees the same kind mix,
- be deterministic given the same seed.
"""

from __future__ import annotations

import json
import random
from pathlib import Path

from conftest import write_jsonl_rows
from merge_and_format import (
    _build_manifest,
    _dedupe,
    _load_rows,
    _stratified_split,
)


def test_load_rows_keeps_only_instruction_fields(tmp_jsonl: Path) -> None:
    write_jsonl_rows(
        tmp_jsonl,
        [
            {
                "prompt": "Use cat.",
                "response": "The cat sleeps.",
                "kind": "sentence",
                "cefr": "A1",
                "word": "cat",
                "source": "test",
                "junk_field": "dropped",
            },
            {"prompt": "  ", "response": "x", "kind": "sentence"},  # blank prompt
            {"prompt": "y", "response": "", "kind": "sentence"},  # blank response
            {"prompt": "no response"},  # missing response
        ],
    )

    rows = _load_rows(tmp_jsonl)

    assert len(rows) == 1
    assert set(rows[0].keys()) == {
        "prompt",
        "response",
        "kind",
        "cefr",
        "word",
        "source",
    }
    assert "junk_field" not in rows[0]


def test_load_rows_returns_empty_for_missing_file(tmp_path: Path) -> None:
    assert _load_rows(tmp_path / "does_not_exist.jsonl") == []


def test_dedupe_drops_identical_prompt_response_pairs() -> None:
    rows = [
        {"prompt": "p1", "response": "r1", "kind": "sentence"},
        {"prompt": "p1", "response": "r1", "kind": "sentence"},  # dup
        {"prompt": "p1", "response": "r2", "kind": "sentence"},  # same prompt, diff response
        {"prompt": "p2", "response": "r1", "kind": "sentence"},  # same response, diff prompt
    ]

    result = _dedupe(rows)

    assert len(result) == 3


def test_stratified_split_keeps_kind_mix_in_each_split() -> None:
    rows = []
    for kind in ("sentence", "story", "explanation"):
        for i in range(100):
            rows.append({"prompt": f"p-{kind}-{i}", "response": "r", "kind": kind})

    rng = random.Random(42)
    train, val, test = _stratified_split(
        rows, val_fraction=0.1, test_fraction=0.1, rng=rng
    )

    def _kinds(split):
        out = {}
        for row in split:
            out[row["kind"]] = out.get(row["kind"], 0) + 1
        return out

    # Each split must contain all three kinds (stratification).
    assert set(_kinds(train)) == {"sentence", "story", "explanation"}
    assert set(_kinds(val)) == {"sentence", "story", "explanation"}
    assert set(_kinds(test)) == {"sentence", "story", "explanation"}
    # Approximate split sizes (10% val + 10% test of 300 = 30/30/240).
    assert len(test) == 30
    assert len(val) == 30
    assert len(train) == 240


def test_stratified_split_is_deterministic_given_seed() -> None:
    rows = [
        {"prompt": f"p-{i}", "response": "r", "kind": "sentence"} for i in range(50)
    ]

    a = _stratified_split(rows, val_fraction=0.1, test_fraction=0.1, rng=random.Random(7))
    b = _stratified_split(rows, val_fraction=0.1, test_fraction=0.1, rng=random.Random(7))

    assert a == b


def test_build_manifest_counts_per_kind_and_source() -> None:
    train = [
        {"kind": "sentence", "source": "tpl"},
        {"kind": "sentence", "source": "tpl"},
        {"kind": "story", "source": "tatoeba"},
    ]
    val = [{"kind": "sentence", "source": "tpl"}]
    test = [{"kind": "story", "source": "tpl"}]

    manifest = _build_manifest(train=train, val=val, test=test)

    assert manifest["total_rows"] == 5
    assert manifest["splits"] == {"train": 3, "validation": 1, "test": 1}
    assert manifest["by_kind"]["train"] == {"sentence": 2, "story": 1}
    assert manifest["by_source"]["train"] == {"tpl": 2, "tatoeba": 1}
    # Manifest must be JSON-serialisable (it gets written to disk).
    json.dumps(manifest)
