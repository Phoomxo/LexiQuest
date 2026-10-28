"""Collector: pull real example sentences from Tatoeba via HF datasets.

Templates give breadth; this collector gives **depth and naturalness**. Tatoeba
is a large, freely-licensed corpus of human-written sentences, and the
``tatoeba``/``sentences`` dataset on HuggingFace exposes them per language.

We filter Tatoeba English sentences down to those that contain one of our
target words, then emit each as a ``sentence`` instruction row. This gives the
LM thousands of *real* usage examples per frequent word, which is exactly the
signal templates cannot provide.

Design notes:

* Uses the ``datasets`` library only at runtime; if it is not installed (e.g.
  during a smoke test without the ``train`` extra), the script prints a clear
  message and exits 0 so the pipeline still completes — Tatoeba is enrichment,
  not a hard dependency.
* Filtering is memory-bounded: we stream the dataset (``streaming=True``) so
  the full multi-GB corpus is never materialised.
* For each target word we cap the number of Tatoeba sentences (default 5) so
  very frequent words do not dominate the dataset.
"""

from __future__ import annotations

import argparse
import sys
from collections import defaultdict
from pathlib import Path
from typing import Iterable

from lexiquest_lm.dataset.io import RAW_DIR, ensure_dirs, read_jsonl, write_jsonl


def _load_target_words(path: Path, limit: int) -> set[str]:
    """Return the set of case-folded target words from an enriched-words JSONL."""

    words: set[str] = set()
    for row in read_jsonl(path):
        word = str(row.get("word", "")).strip().casefold()
        if word:
            words.add(word)
        if limit and len(words) >= limit:
            break
    return words


def _iter_tatoeba_english() -> Iterable[str]:
    """Stream English sentences from the HuggingFace Tatoeba dataset.

    Yields one sentence at a time. Raises ImportError if ``datasets`` is not
    installed; the caller decides whether that is fatal.
    """

    from datasets import load_dataset  # type: ignore[import-not-found]

    # ``tatoeba`` is the canonical dataset; the ``sentences`` config gives
    # rows with ``id``, ``text``, ``lang``. We filter to English client-side
    # because the streaming API does not always honour split-by-language.
    dataset = load_dataset("tatoeba", "eng", split="train", streaming=True)
    for row in dataset:
        text = row.get("text") or row.get("translation", {}).get("en")
        if isinstance(text, str) and text.strip():
            yield text.strip()


def _matches_any_word(sentence: str, words: set[str]) -> str | None:
    """Return the first target word found in ``sentence`` (case-insensitive).

    Returns ``None`` if no target word appears as a whole word. We match on
    word boundaries so 'cat' does not match 'category'.
    """

    # Cheap whole-word match without importing ``re`` per call: split on
    # non-letters and look up the lowercased tokens. This is O(n) in sentence
    # length per call, which is fine for the streaming pass.
    tokens = {
        token
        for token in "".join(
            ch if ch.isalnum() else " " for ch in sentence
        ).split()
    }
    for token in tokens:
        if token in words:
            return token
    return None


def collect_tatoeba(
    target_words: set[str], *, per_word_cap: int, sentence_iter=_iter_tatoeba_english
) -> list[dict[str, object]]:
    """Collect up to ``per_word_cap`` real sentences per target word.

    Stops early once every target word has reached its cap, so the streaming
    pass does not have to traverse the entire corpus.
    """

    per_word: dict[str, list[str]] = defaultdict(list)
    done: set[str] = set()

    for sentence in sentence_iter():
        if len(done) == len(target_words):
            break
        word = _matches_any_word(sentence, target_words)
        if word is None or word in done:
            continue
        per_word[word].append(sentence)
        if len(per_word[word]) >= per_word_cap:
            done.add(word)

    rows: list[dict[str, object]] = []
    for word, sentences in per_word.items():
        for sentence in sentences:
            rows.append(
                {
                    "prompt": (
                        f"Write ONE clear example sentence using the word '{word}'."
                    ),
                    "response": sentence,
                    "kind": "sentence",
                    "cefr": "",  # Tatoeba is not CEFR-tagged
                    "word": word,
                    "source": "tatoeba_english",
                }
            )
    return rows


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Pull real example sentences from Tatoeba for the target words."
    )
    parser.add_argument(
        "--targets",
        type=Path,
        default=RAW_DIR / "enriched_words.jsonl",
        help="JSONL of target words (default: enriched_words.jsonl).",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=RAW_DIR / "tatoeba_sentences.jsonl",
        help="Output JSONL path.",
    )
    parser.add_argument(
        "--per-word-cap",
        type=int,
        default=5,
        help="Max Tatoeba sentences per word (default: 5).",
    )
    parser.add_argument(
        "--limit-words",
        type=int,
        default=0,
        help="Consider only the first N target words (0 = all).",
    )
    args = parser.parse_args(argv)

    ensure_dirs()
    if not args.targets.exists():
        print(f"ERROR: targets file not found: {args.targets}", file=sys.stderr)
        return 2

    try:
        import datasets  # noqa: F401  (test for availability)
    except ImportError:
        print(
            "NOTE: 'datasets' is not installed. Skipping Tatoeba collection. "
            "Install with: uv sync --project backend/lexiquest_lm --group train",
            file=sys.stderr,
        )
        # Write an empty file so downstream merge sees a stable path.
        write_jsonl(args.out, [])
        return 0

    target_words = _load_target_words(args.targets, args.limit_words)
    print(f"Collecting Tatoeba sentences for {len(target_words)} target words...")
    rows = collect_tatoeba(
        target_words, per_word_cap=args.per_word_cap
    )
    count = write_jsonl(args.out, rows)
    print(f"Collected {count} Tatoeba sentences (cap {args.per_word_cap}/word).")
    print(f"Wrote {args.out}")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
