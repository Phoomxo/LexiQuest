"""Tests for collect_cefr_words.py.

The parser must:
- faithfully extract every CefrWord literal from the Dart source,
- preserve Thai meanings, parts of speech, and tags,
- fail loudly (rather than silently drop words) when the source format changes.
"""

from __future__ import annotations

import pytest

from collect_cefr_words import parse_cefr_source, _parse_tag_list


def test_parse_tag_list_handles_empty_and_quoted() -> None:
    assert _parse_tag_list("") == ()
    assert _parse_tag_list("  ") == ()
    assert _parse_tag_list("'daily'") == ("daily",)
    assert _parse_tag_list("'daily', 'toeic'") == ("daily", "toeic")


def test_parse_extracts_a_complete_a1_entry() -> None:
    source = """
    static const List<CefrWord> defaultCefrDatabase = [
      CefrWord(
        word: 'dog',
        cefrLevel: 'A1',
        category: 'Animals',
        meaning: 'หมา / สุนัข',
        partOfSpeech: 'Noun',
        exampleSentence: 'The dog is barking.',
        tags: ['daily', 'pet'],
      ),
    ];
    """

    records = parse_cefr_source(source)

    assert len(records) == 1
    record = records[0]
    assert record.word == "dog"
    assert record.cefr_level == "A1"
    assert record.category == "Animals"
    assert record.meaning_th == "หมา / สุนัข"
    assert record.part_of_speech == "Noun"
    assert record.example_sentence == "The dog is barking."
    assert record.tags == ("daily", "pet")
    assert record.source == "app_cefr_bank"


def test_parse_extracts_multiple_entries_in_order() -> None:
    source = """
    CefrWord(word: 'apple', cefrLevel: 'A1', category: 'Food',
            meaning: 'แอปเปิ้ล', partOfSpeech: 'Noun',
            exampleSentence: 'She eats an apple.', tags: ['daily']),
    CefrWord(word: 'journey', cefrLevel: 'A2', category: 'Travel',
            meaning: 'การเดินทาง', partOfSpeech: 'Noun',
            exampleSentence: 'Have a safe journey.', tags: ['daily', 'toeic']),
    """

    records = parse_cefr_source(source)

    assert [r.word for r in records] == ["apple", "journey"]
    assert records[1].cefr_level == "A2"
    assert records[1].tags == ("daily", "toeic")


def test_parse_skips_dynamic_word_parameter_literal() -> None:
    """A ``CefrWord(word: word, ...)`` constructed inside a method must be
    skipped, because ``word`` is a variable, not a literal string."""

    source = """
    CefrWord(word: 'real', cefrLevel: 'A1', category: 'X', meaning: '',
             partOfSpeech: '', exampleSentence: '', tags: []),
    factory CefrWord.fromMap(Map<String, dynamic> map) =>
        CefrWord(word: map['word'], cefrLevel: 'A1', category: '',
                 meaning: '', partOfSpeech: '', exampleSentence: '', tags: []);
    """

    records = parse_cefr_source(source)

    # Only the literal ``'real'`` entry should survive; the dynamic one is
    # skipped because its ``word`` field is not a quoted string.
    assert [r.word for r in records] == ["real"]


def test_parse_handles_nested_parentheses_in_meaning() -> None:
    source = """
    CefrWord(word: 'risk', cefrLevel: 'B1', category: 'X',
            meaning: 'ความเสี่ยง (จาก something)',
            partOfSpeech: 'Noun', exampleSentence: '', tags: []),
    """

    records = parse_cefr_source(source)

    assert len(records) == 1
    # The closing paren inside ``meaning`` must not prematurely end the block.
    assert "จาก something" in records[0].meaning_th


def test_parse_raises_on_zero_entries_so_format_drift_is_loud() -> None:
    with pytest.raises(ValueError, match="No CefrWord"):
        parse_cefr_source("// no entries here, just comments\n")
