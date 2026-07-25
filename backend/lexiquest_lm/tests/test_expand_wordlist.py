"""Tests for expand_wordlist.py."""

from __future__ import annotations

from expand_wordlist import build_expansion, dedupe_against_seed
from lexiquest_lm.dataset.io import CefrWord


def test_build_expansion_returns_unique_words() -> None:
    expansion = build_expansion()

    assert len(expansion) > 100  # we bundled hundreds of words
    words = [w.word.casefold() for w in expansion]
    assert len(set(words)) == len(words), "expansion contains duplicate words"


def test_build_expansion_tags_each_source() -> None:
    expansion = build_expansion()

    sources = {w.source for w in expansion}
    assert "oxford_3000_a1" in sources
    assert "oxford_3000_a2" in sources
    assert "cefrj_b2_c1" in sources


def test_build_expansion_assigns_cefr_level_per_band() -> None:
    expansion = build_expansion()

    a1 = [w for w in expansion if w.source == "oxford_3000_a1"]
    a2 = [w for w in expansion if w.source == "oxford_3000_a2"]
    assert all(w.cefr_level == "A1" for w in a1)
    assert all(w.cefr_level == "A2" for w in a2)


def test_dedupe_drops_words_present_in_seed() -> None:
    expansion = [
        CefrWord(word="apple", cefr_level="A1", source="oxford_3000_a1"),
        CefrWord(word="journey", cefr_level="A2", source="oxford_3000_a2"),
        CefrWord(word="innovative", cefr_level="B2", source="cefrj_b2_c1"),
    ]

    result = dedupe_against_seed(expansion, seed_words={"apple", "journey"})

    assert [w.word for w in result] == ["innovative"]


def test_dedupe_is_case_insensitive() -> None:
    expansion = [
        CefrWord(word="Apple", cefr_level="A1", source="oxford_3000_a1"),
        CefrWord(word="Banana", cefr_level="A1", source="oxford_3000_a1"),
    ]

    result = dedupe_against_seed(expansion, seed_words={"apple"})

    assert [w.word for w in result] == ["Banana"]
