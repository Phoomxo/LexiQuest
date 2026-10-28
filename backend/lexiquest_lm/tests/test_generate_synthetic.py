"""Tests for generate_synthetic.py.

The generator must:
- produce POS-correct sentences (a preposition never fills a noun slot),
- respect CEFR level (fall back to a lower band when the exact one is empty),
- emit exactly one explanation per word,
- be deterministic given the same seed.
"""

from __future__ import annotations

import random

from generate_synthetic import (
    GeminiAugmenter,
    _explanation_response,
    _format_template,
    _pos_family,
    _templates_for_level_and_pos,
    generate_template_rows,
)
from lexiquest_lm.dataset.io import CefrWord


def _word(**overrides: object) -> CefrWord:
    base: dict[str, object] = {
        "word": "cat",
        "cefr_level": "A1",
        "part_of_speech": "Noun",
        "category": "Animals",
        "tags": ("kitten",),
    }
    base.update(overrides)
    return CefrWord(**base)  # type: ignore[arg-type]


# ---------------------------------------------------------------------------
# POS family mapping
# ---------------------------------------------------------------------------


def test_pos_family_maps_common_variants() -> None:
    assert _pos_family("Noun") == "noun"
    assert _pos_family("Transitive Verb") == "verb"
    assert _pos_family("Adjective") == "adjective"
    assert _pos_family("Adverb") == "adverb"
    assert _pos_family("Preposition") == "function"
    assert _pos_family("Conjunction") == "function"
    assert _pos_family("Interjection") == "function"
    assert _pos_family("") == "any"
    assert _pos_family("UnknownThing") == "any"


# ---------------------------------------------------------------------------
# Template selection
# ---------------------------------------------------------------------------


def test_templates_return_pos_match_when_available() -> None:
    templates = _templates_for_level_and_pos(
        [("A1", "noun", "The {w}."), ("A1", "verb", "I {w}.")],
        target_level="A1",
        pos_family="verb",
    )
    assert templates == ["I {w}."]


def test_templates_fall_back_to_lower_level() -> None:
    templates = _templates_for_level_and_pos(
        [
            ("A1", "noun", "The {w}."),
            ("B2", "noun", "The {w}, which is debated."),
        ],
        target_level="C1",
        pos_family="noun",
    )
    # C1 has no noun templates; we walk down to B2 (the nearest lower band).
    assert templates == ["The {w}, which is debated."]


def test_templates_fall_back_to_any_when_pos_missing() -> None:
    templates = _templates_for_level_and_pos(
        [
            ("A1", "noun", "The {w}."),
            ("A1", "any", "I learned {w}."),
        ],
        target_level="A1",
        pos_family="function",
    )
    # No A1/function templates -> fall back to A1/any.
    assert templates == ["I learned {w}."]


# ---------------------------------------------------------------------------
# Generation correctness
# ---------------------------------------------------------------------------


def test_generate_emits_at_least_one_of_each_kind() -> None:
    rng = random.Random(0)
    rows = generate_template_rows(_word(), rng=rng)

    kinds = {row["kind"] for row in rows}
    assert {"sentence", "story", "explanation"} <= kinds


def test_generate_produces_pos_correct_sentence_for_verb() -> None:
    rng = random.Random(0)
    rows = generate_template_rows(
        _word(word="accept", part_of_speech="Verb"), rng=rng
    )

    sentences = [str(r["response"]) for r in rows if r["kind"] == "sentence"]
    # A verb must slot into a verb template; it must never read like a noun.
    assert any("accept" in s for s in sentences)
    assert not any(s.startswith("The accept") for s in sentences), sentences


def test_generate_produces_pos_correct_sentence_for_preposition() -> None:
    rng = random.Random(0)
    rows = generate_template_rows(
        _word(word="about", part_of_speech="Preposition"), rng=rng
    )

    sentences = [str(r["response"]) for r in rows if r["kind"] == "sentence"]
    assert sentences, "expected at least one sentence"
    # A preposition must never fill a noun slot.
    assert not any("The about" in s for s in sentences), sentences


def test_generate_is_deterministic_given_seed() -> None:
    rows_a = generate_template_rows(_word(), rng=random.Random(42))
    rows_b = generate_template_rows(_word(), rng=random.Random(42))

    assert rows_a == rows_b


def test_explanation_uses_enriched_fields() -> None:
    response = _explanation_response(
        _word(
            word="dog",
            part_of_speech="Noun",
            category="Animals",
            meaning_th="หมา",
            tags=("puppy", "hound", "pet"),
        )
    )

    assert "noun" in response
    assert "animals" in response
    assert "หมา" in response
    assert "puppy" in response


def test_format_template_uses_synonym_when_available() -> None:
    formatted = _format_template("The {syn} is here.", _word(tags=("kitten",)))
    assert "kitten" in formatted


# ---------------------------------------------------------------------------
# Gemini augmenter is opt-in
# ---------------------------------------------------------------------------


def test_gemini_augmenter_disabled_when_no_env_key(monkeypatch) -> None:
    monkeypatch.delenv("LEXIQUEST_LM_GEMINI_KEY", raising=False)
    assert GeminiAugmenter.from_env() is None
