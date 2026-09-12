"""Maintained seed/expansion union coverage using actual temporary JSONL."""

from __future__ import annotations

import json

import pytest

import enrich_dictionary
from lexiquest_lm.dataset import io as dataset_io


@pytest.fixture
def dictionary_transport(monkeypatch, tmp_path):
    # Redirect only the dataset module's directory configuration, never Path.
    monkeypatch.setattr(dataset_io, "RAW_DIR", tmp_path / "raw")
    monkeypatch.setattr(dataset_io, "PROCESSED_DIR", tmp_path / "processed")
    calls = []

    def get_json(url, timeout):
        calls.append(url)
        if "api.datamuse.com" in url:
            return [{"word": "api-synonym"}]
        return [{"meanings": [{
            "partOfSpeech": "api-pos",
            "definitions": [{"example": "API example."}],
        }]}]

    monkeypatch.setattr(enrich_dictionary, "_http_get_json", get_json)
    return calls


def _write_rows(path, rows):
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows),
        encoding="utf-8",
    )


def _enrich(tmp_path, seed, expanded, *, limit=0, name="result"):
    seed_path = tmp_path / "seed.jsonl"
    input_path = tmp_path / "expanded.jsonl"
    out_path = tmp_path / f"{name}.jsonl"
    _write_rows(seed_path, seed)
    _write_rows(input_path, expanded)
    assert enrich_dictionary.main([
        "--seed", str(seed_path), "--input", str(input_path),
        "--out", str(out_path), "--delay", "0", "--limit", str(limit),
    ]) == 0
    return [json.loads(line) for line in out_path.read_text(encoding="utf-8").splitlines()]


def test_enrichment_unions_seed_only_overlap_and_expanded_only(
    tmp_path, dictionary_transport
):
    curated = {
        "word": "Cat", "cefr_level": "A1", "meaning_th": "แมว",
        "part_of_speech": "Noun", "example_sentence": "Curated cat.",
        "category": "Animals", "tags": ["curated"], "source": "seed",
    }
    rows = _enrich(
        tmp_path,
        [{"word": "seed-only", "cefr_level": "A2"}, curated],
        [
            {
                "word": "cAT", "cefr_level": "C1", "meaning_th": "wrong",
                "part_of_speech": "Verb", "example_sentence": "Expanded cat.",
                "category": "Wrong", "tags": ["expanded"],
            },
            {"word": "expanded-only", "cefr_level": "B1"},
        ],
    )
    by_word = {row["word"].casefold(): row for row in rows}
    assert len(rows) == len(by_word) == 3
    assert set(by_word) == {"seed-only", "cat", "expanded-only"}
    for field in (
        "cefr_level", "meaning_th", "part_of_speech",
        "example_sentence", "category", "tags",
    ):
        assert by_word["cat"][field] == curated[field]
    assert by_word["seed-only"]["example_sentence"] == "API example."
    assert by_word["expanded-only"]["tags"] == ["api-synonym"]


def test_enrichment_keeps_expanded_nonempty_fields_when_curated_fields_empty(
    tmp_path, dictionary_transport
):
    expanded = {
        "word": "cat", "cefr_level": "A2", "meaning_th": "expanded meaning",
        "part_of_speech": "Noun", "example_sentence": "Expanded example.",
        "category": "Animals", "tags": ["expanded-tag"],
    }
    rows = _enrich(
        tmp_path,
        [{"word": "CAT", "cefr_level": "", "meaning_th": "แมว"}],
        [expanded],
    )
    assert len(rows) == 1
    assert rows[0]["meaning_th"] == "แมว"
    for field in (
        "cefr_level", "part_of_speech", "example_sentence", "category", "tags",
    ):
        assert rows[0][field] == expanded[field]
    assert len(dictionary_transport) == 1  # existing tags need no API fallback


def test_enrichment_deduplicates_casefold_union_before_deterministic_limit(
    tmp_path, dictionary_transport
):
    seed = [
        {"word": "Seed-only", "cefr_level": "A1", "tags": ["fixed"]},
        {"word": "ALPHA", "cefr_level": "A1", "tags": ["fixed"]},
    ]
    expanded = [
        {"word": "alpha", "cefr_level": "A1", "tags": ["fixed"]},
        {"word": "Alpha", "cefr_level": "A1", "tags": ["fixed"]},
        {"word": "beta", "cefr_level": "A1", "tags": ["fixed"]},
    ]
    full = _enrich(tmp_path, seed, expanded, name="full")
    assert len(full) == 3
    assert {row["word"].casefold() for row in full} == {"seed-only", "alpha", "beta"}
    assert len(dictionary_transport) == 3  # duplicates are not enriched twice

    first = _enrich(tmp_path, seed, expanded, limit=2, name="first")
    second = _enrich(tmp_path, seed, expanded, limit=2, name="second")
    assert first == second == full[:2]
    assert len({row["word"].casefold() for row in first}) == 2
    assert len(dictionary_transport) == 7
