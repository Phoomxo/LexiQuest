"""Collector: synthesise teaching examples for every word.

This is the **volume generator** that takes the 1862 enriched words and turns
each into many instruction-tuning rows. We use a **hybrid** strategy so the
dataset can be built in a single day without burning LLM quota up front:

1. **Template-based generation (primary, no API key)** — deterministic
   templates per content kind (sentence / story / explanation) seeded by the
   word's enriched fields (POS, category, synonyms). Multiple template
   variants per kind multiply rows without diversity loss because each variant
   is a legitimately different sentence shape.
2. **Gemini generation (optional, opt-in)** — when ``LEXIQUEST_LM_GEMINI_KEY``
   is set, a configurable fraction of rows are *augmented* (rephrased /
   expanded) by Gemini to add natural-language diversity on top of the
   template backbone. This never blocks the run: a missing/failed Gemini call
   simply falls back to the template output.

Design notes:

* All outputs are instruction-tuning rows: ``{"prompt": ..., "response": ...}``
  so the formatter downstream does almost nothing.
* Templates are CEFR-aware (A1 uses simple present, B2+ uses subordinate
  clauses) so the LM learns level-appropriate phrasing, not just words.
* The generator is deterministic given its seed, so two runs produce the
  identical dataset (important for reproducibility / thesis evidence).
* Gemini, when enabled, honours a per-minute throttle so the free-tier 15 RPM
  ceiling is never breached.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Iterable

from lexiquest_lm.dataset.io import (
    CefrWord,
    RAW_DIR,
    ensure_dirs,
    read_jsonl,
    write_jsonl,
)

# ---------------------------------------------------------------------------
# Instruction-tuning row shape
# ---------------------------------------------------------------------------

# A single training example. ``source`` records which generator produced it
# ("template_sentence_a1", "gemini_story", etc.) so we can later analyse the
# dataset composition and so a human reviewer can audit it by source.
_INSTRUCTION_KEYS = ("prompt", "response", "kind", "cefr", "source", "word")


def _row(
    *,
    prompt: str,
    response: str,
    kind: str,
    word: CefrWord,
    source: str,
) -> dict[str, object]:
    return {
        "prompt": prompt,
        "response": response,
        "kind": kind,
        "cefr": word.cefr_level,
        "word": word.word,
        "source": source,
    }


# ---------------------------------------------------------------------------
# Prompt templates per kind. These are the backbone of every generated row.
# ---------------------------------------------------------------------------

# Sentences are level-stratified AND part-of-speech aware. A noun fits
# ``The {w} is here.`` but a preposition like ``about`` does not, so each
# template is tagged with the POS family it suits. ``{w}`` is the word,
# ``{pos}`` its part of speech, ``{cat}`` its category, ``{syn}`` a synonym.
# Tuple shape: (cefr_band, pos_family, template).
_SENTENCE_TEMPLATES: list[tuple[str, str, str]] = [
    # --- Nouns ---
    ("A1", "noun", "The {w} is here."),
    ("A1", "noun", "She has a {w}."),
    ("A1", "noun", "Look at the {w}."),
    ("A1", "noun", "This {w} is new."),
    ("A1", "noun", "We see a {w} today."),
    ("A2", "noun", "My friend bought a new {w} yesterday."),
    ("A2", "noun", "The {w} in this room is very useful."),
    ("B1", "noun", "Although the {w} seemed ordinary, it changed everything."),
    ("B1", "noun", "The teacher explained the {w} with several clear examples."),
    ("B2", "noun", "The {w}, which scholars have debated for decades, remains controversial."),
    ("C1", "noun", "The {w} epitomises the tension between tradition and innovation."),
    # --- Verbs ---
    ("A1", "verb", "I {w} every day."),
    ("A1", "verb", "She will {w} soon."),
    ("A1", "verb", "We {w} together."),
    ("A2", "verb", "They always {w} in the morning."),
    ("A2", "verb", "He learned to {w} last year."),
    ("B1", "verb", "If you {w} carefully, the result improves."),
    ("B1", "verb", "She continued to {w} despite the difficulty."),
    ("B2", "verb", "The committee decided to {w} after a long debate."),
    ("C1", "verb", "To {w} effectively requires both practice and insight."),
    # --- Adjectives ---
    ("A1", "adjective", "The {w} cat is sleeping."),
    ("A1", "adjective", "She is {w}."),
    ("A1", "adjective", "I have a {w} book."),
    ("A2", "adjective", "The weather is very {w} today."),
    ("A2", "adjective", "He bought a {w} car last week."),
    ("B1", "adjective", "The result was surprisingly {w}."),
    ("B1", "adjective", "She found the topic both {w} and challenging."),
    ("B2", "adjective", "His argument, though {w}, failed to convince everyone."),
    ("C1", "adjective", "The proposal was as {w} as it was controversial."),
    # --- Adverbs ---
    ("A1", "adverb", "She runs {w}."),
    ("A1", "adverb", "He spoke {w} to the class."),
    ("A2", "adverb", "They finished the work {w}."),
    ("B1", "adverb", "He answered {w}, even though he was unsure."),
    ("B2", "adverb", "The data, analysed {w}, revealed a clear trend."),
    # --- Prepositions / Conjunctions / Determiners (function words) ---
    ("A1", "function", "The book is {w} the table."),
    ("A1", "function", "We walked {w} the river."),
    ("A2", "function", "She sat {w} her friend during the show."),
    ("B1", "function", "The answer depends {w} how you frame the question."),
    # --- Universal fallback (works for any POS, talks about the word) ---
    ("A1", "any", "I like the word {w}."),
    ("A1", "any", "I learned the word {w} in class."),
    ("A2", "any", "Can you explain what {w} means?"),
    ("B1", "any", "He described {w} in a way that everyone could follow."),
    ("B2", "any", "Researchers continue to investigate {w} from multiple perspectives."),
    ("C1", "any", "A nuanced grasp of {w} is indispensable for advanced discourse."),
]

# Micro-stories: 2-4 sentences using the target word in context. Stories use
# the word as a noun by default because that is the most common case; for
# other POS families we fall back to the universal ``any`` story templates.
_STORY_TEMPLATES: list[tuple[str, str, str]] = [
    ("A1", "noun", "Ana sees a {w}. The {w} is big. She is happy."),
    ("A1", "noun", "Tom has a {w}. He plays with the {w}. It is fun."),
    ("A2", "noun", "Mai lost her {w} this morning. She looked everywhere. At noon, she found it under the bed."),
    ("A2", "noun", "The old {w} stopped working. Dad tried to fix it. Finally, he bought a new one."),
    ("B1", "noun", "Lena had never seen a {w} before. Curious, she read about it all evening. By morning, she understood it well."),
    ("B2", "noun", "The committee debated the {w} for hours. Opinions clashed, evidence was weighed. In the end, they reached a careful compromise."),
    ("C1", "noun", "For centuries the {w} had been taken for granted. Then a young scholar questioned it, and an entire field was upended."),
    ("A1", "verb", "Tom likes to {w}. He {w}s every morning. It makes him happy."),
    ("A2", "verb", "Mai learned to {w} last summer. She practised daily. Now she can {w} well."),
    ("B1", "verb", "Lena tried to {w} but failed at first. She kept trying. After weeks, she succeeded."),
    ("A1", "adjective", "The day was {w}. The {w} weather felt nice. We stayed outside."),
    ("A2", "adjective", "He bought a {w} shirt. The {w} colour suited him. Everyone liked it."),
    ("A1", "any", "Today we learned the word {w}. {w} is interesting. We want to use it again."),
    ("A2", "any", "Our teacher wrote {w} on the board. She explained {w} slowly. Soon we all understood."),
    ("B1", "any", "Today we explored {w}. {w} is interesting. We want to learn more about it."),
    ("B2", "any", "The professor lectured about {w}. The students took notes carefully. By the end, they understood {w} deeply."),
]

# Explanations: short definitional text using the word's enriched fields.
def _explanation_response(word: CefrWord) -> str:
    pos = word.part_of_speech or "word"
    category = word.category or "general use"
    meaning = f' It means "{word.meaning_th}".' if word.meaning_th else ""
    synonyms = ", ".join(word.tags[:3]) if word.tags else ""
    syn_clause = f" Words with a similar meaning include {synonyms}." if synonyms else ""
    return (
        f"The word '{word.word}' is a {pos.lower()} used in {category.lower()}.{meaning}"
        f" It belongs to the {word.cefr_level or 'A1'} level.{syn_clause}"
    )


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------


def _pos_family(part_of_speech: str) -> str:
    """Map a free-text part of speech to one of the template families.

    The dictionary API uses many variants (``Noun``, ``Transitive Verb``,
    ``Adjective`` etc.); templates only need a coarse family.
    """

    pos = (part_of_speech or "").lower()
    if any(k in pos for k in ("noun",)):
        return "noun"
    if any(k in pos for k in ("verb",)):
        return "verb"
    if any(k in pos for k in ("adjective",)):
        return "adjective"
    if any(k in pos for k in ("adverb",)):
        return "adverb"
    if any(k in pos for k in ("preposition", "conjunction", "determiner", "pronoun", "article", "modal")):
        return "function"
    return "any"


def _templates_for_level_and_pos(
    templates: list[tuple[str, str, str]],
    target_level: str,
    pos_family: str,
) -> list[str]:
    """Pick templates matching both the CEFR band and the POS family.

    Two-stage fallback so every word gets templates:
      1. exact (level, pos_family) match
      2. nearest lower level for that pos_family
      3. ``any`` family at the target level
      4. ``any`` family at the nearest lower level
    """

    order = ["A1", "A2", "B1", "B2", "C1", "C2"]
    target_idx = order.index(target_level) if target_level in order else 0

    # Stage 1+2: exact POS family, walk down levels.
    for idx in range(target_idx, -1, -1):
        band = order[idx]
        matches = [t for level, fam, t in templates if level == band and fam == pos_family]
        if matches:
            return matches
    # Stage 3+4: ``any`` family fallback.
    for idx in range(target_idx, -1, -1):
        band = order[idx]
        matches = [t for level, fam, t in templates if level == band and fam == "any"]
        if matches:
            return matches
    return [t for _, _, t in templates]


def _format_template(template: str, word: CefrWord) -> str:
    syn = word.tags[0] if word.tags else word.word
    return template.format(
        w=word.word,
        pos=word.part_of_speech or "thing",
        cat=word.category or "general",
        syn=syn,
    )


def _sentence_prompt(word: CefrWord) -> str:
    return (
        f"Write ONE clear example sentence using the word '{word.word}' "
        f"at CEFR level {word.cefr_level or 'A1'}."
    )


def _story_prompt(word: CefrWord) -> str:
    return (
        f"Write a short micro-story (2-4 sentences) that uses the word "
        f"'{word.word}' in context at CEFR level {word.cefr_level or 'A1'}."
    )


def _explanation_prompt(word: CefrWord) -> str:
    return f"Explain the word '{word.word}' in simple terms."


def generate_template_rows(
    word: CefrWord, *, rng: random.Random
) -> list[dict[str, object]]:
    """Generate all template-based rows for one word.

    Yields ~6-10 rows per word: 3 sentences (POS-aware), 1-2 stories, and
    1 explanation. Templates are selected by (CEFR level, POS family) so a
    preposition never lands in a noun-shaped slot.
    """

    rows: list[dict[str, object]] = []
    pos_family = _pos_family(word.part_of_speech)

    sentence_templates = _templates_for_level_and_pos(
        _SENTENCE_TEMPLATES, word.cefr_level, pos_family
    )
    chosen_sentences = rng.sample(
        sentence_templates, k=min(3, len(sentence_templates))
    )
    for template in chosen_sentences:
        rows.append(
            _row(
                prompt=_sentence_prompt(word),
                response=_format_template(template, word),
                kind="sentence",
                word=word,
                source=f"template_sentence_{word.cefr_level.lower() or 'a1'}_{pos_family}",
            )
        )

    story_templates = _templates_for_level_and_pos(
        _STORY_TEMPLATES, word.cefr_level, pos_family
    )
    chosen_stories = rng.sample(
        story_templates, k=min(2, len(story_templates))
    )
    for template in chosen_stories:
        rows.append(
            _row(
                prompt=_story_prompt(word),
                response=_format_template(template, word),
                kind="story",
                word=word,
                source=f"template_story_{word.cefr_level.lower() or 'a1'}_{pos_family}",
            )
        )

    rows.append(
        _row(
            prompt=_explanation_prompt(word),
            response=_explanation_response(word),
            kind="explanation",
            word=word,
            source="template_explanation",
        )
    )

    return rows


# ---------------------------------------------------------------------------
# Optional Gemini augmentation
# ---------------------------------------------------------------------------


class GeminiAugmenter:
    """Opt-in Gemini rephraser that diversifies template outputs.

    Enabled only when ``LEXIQUEST_LM_GEMINI_KEY`` is set. When disabled, the
    generator runs entirely on templates — Gemini is never called. When
    enabled, a configurable fraction of rows are sent to Gemini with a
    "rephrase more naturally" instruction; failures fall back to the original.
    """

    _URL = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
    _MODEL = "gemini-2.0-flash"

    def __init__(
        self,
        *,
        api_key: str,
        rpm_limit: int = 15,
        delay_seconds: float = 4.5,
    ) -> None:
        # 4.5s spacing => ~13 RPM, leaving headroom under the 15 RPM free tier.
        self._api_key = api_key
        self._delay = delay_seconds
        self._rpm_limit = rpm_limit
        self._last_call = 0.0

    @classmethod
    def from_env(cls) -> "GeminiAugmenter | None":
        key = os.environ.get("LEXIQUEST_LM_GEMINI_KEY", "").strip()
        if not key:
            return None
        return cls(api_key=key)

    def augment(self, prompt: str, response: str, *, kind: str) -> str:
        """Rephrase ``response`` more naturally via Gemini. Falls back on error."""

        # Throttle: never exceed the configured RPM. Sleep the remainder.
        elapsed = time.monotonic() - self._last_call
        if elapsed < self._delay:
            time.sleep(self._delay - elapsed)
        self._last_call = time.monotonic()

        instruction = (
            f"Rewrite the following {kind} so it sounds more natural and "
            f"varied, keeping it at the same difficulty level. Reply with "
            f"ONLY the rewritten {kind}, no preamble.\n\nOriginal: {response}"
        )
        payload = json.dumps(
            {
                "model": self._MODEL,
                "messages": [
                    {"role": "system", "content": "You are an English vocabulary teacher."},
                    {"role": "user", "content": instruction},
                ],
                "temperature": 0.7,
                "max_tokens": 200,
            }
        ).encode("utf-8")
        req = urllib.request.Request(
            self._URL,
            data=payload,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self._api_key}",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:  # noqa: S310
                decoded = json.loads(resp.read().decode("utf-8"))
            text = decoded["choices"][0]["message"]["content"]
            return text.strip() if isinstance(text, str) and text.strip() else response
        except (urllib.error.URLError, TimeoutError, OSError, ValueError, KeyError, IndexError):
            return response


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Generate synthetic instruction-tuning rows for every word."
    )
    parser.add_argument(
        "--input",
        type=Path,
        default=RAW_DIR / "enriched_words.jsonl",
        help="Input JSONL of enriched words (default: enriched_words.jsonl).",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=RAW_DIR / "synthetic_examples.jsonl",
        help="Output JSONL path.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Generate for only the first N words (0 = all).",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for deterministic template sampling (default: 42).",
    )
    parser.add_argument(
        "--gemini-fraction",
        type=float,
        default=0.0,
        help=(
            "Fraction of rows to augment via Gemini (0.0-1.0, default 0.0). "
            "Ignored unless LEXIQUEST_LM_GEMINI_KEY is set."
        ),
    )
    args = parser.parse_args(argv)

    if not 0.0 <= args.gemini_fraction <= 1.0:
        print("ERROR: --gemini-fraction must be between 0 and 1", file=sys.stderr)
        return 2

    ensure_dirs()
    if not args.input.exists():
        print(f"ERROR: input not found: {args.input}", file=sys.stderr)
        return 2

    words: list[CefrWord] = []
    for row in read_jsonl(args.input):
        word_str = str(row.get("word", "")).strip()
        if not word_str:
            continue
        tags_raw = row.get("tags") or []
        tags = tuple(str(t) for t in tags_raw) if isinstance(tags_raw, list) else ()
        words.append(
            CefrWord(
                word=word_str,
                cefr_level=str(row.get("cefr_level", "")),
                meaning_th=str(row.get("meaning_th", "")),
                part_of_speech=str(row.get("part_of_speech", "")),
                example_sentence=str(row.get("example_sentence", "")),
                category=str(row.get("category", "")),
                tags=tags,
                source=str(row.get("source", "")),
            )
        )
    if args.limit > 0:
        words = words[: args.limit]

    rng = random.Random(args.seed)
    augmenter = GeminiAugmenter.from_env()
    gemini_enabled = augmenter is not None and args.gemini_fraction > 0.0
    if args.gemini_fraction > 0.0 and augmenter is None:
        print(
            "NOTE: --gemini-fraction > 0 but LEXIQUEST_LM_GEMINI_KEY is not set; "
            "running template-only.",
            file=sys.stderr,
        )

    print(f"Generating rows for {len(words)} words (seed={args.seed})...")
    all_rows: list[dict[str, object]] = []
    for index, word in enumerate(words, start=1):
        rows = generate_template_rows(word, rng=rng)
        if gemini_enabled:
            for row in rows:
                if rng.random() < args.gemini_fraction:
                    augmented = augmenter.augment(
                        str(row["prompt"]), str(row["response"]), kind=str(row["kind"])
                    )
                    if augmented != row["response"]:
                        row["response"] = augmented
                        row["source"] = f"gemini_{row['source']}"
        all_rows.extend(rows)
        if index % 200 == 0:
            print(f"  generated rows for {index} words ({len(all_rows)} total)...")

    count = write_jsonl(args.out, all_rows)
    by_kind: dict[str, int] = {}
    for r in all_rows:
        by_kind[str(r["kind"])] = by_kind.get(str(r["kind"]), 0) + 1
    breakdown = ", ".join(f"{k}={v}" for k, v in sorted(by_kind.items()))
    print(f"Generated {count} rows ({breakdown}).")
    print(f"Wrote {args.out}")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
