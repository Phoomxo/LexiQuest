"""Collector: enrich words with definitions and example sentences.

The expanded wordlist has English word + CEFR level + part of speech but no
Thai meaning or example sentence. This collector fills those gaps from two
free, no-auth, dictionary APIs:

1. **dictionaryapi.dev** (Free Dictionary API) — English definitions, parts of
   speech, and example sentences. The primary source for ``example_sentence``
   because most entries ship a real usage example.
2. **Datamuse** — synonyms, antonyms, and "kind-of" relations. Used to enrich
   ``tags`` (synonyms become related-word tags) and as a fallback signal that
   a word is well-formed.

Both APIs are free and require no key, so the run is fully reproducible from a
fresh checkout. To stay polite (and within their implicit rate expectations)
we throttle to a configurable delay between requests and never parallelise.

Output: ``data/raw/enriched_words.jsonl``. Each row is the input ``CefrWord``
with ``meaning_th``/``example_sentence`` filled where a source provided one,
and ``source`` updated to record which source contributed (for provenance).
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Iterable

from lexiquest_lm.dataset.io import CefrWord, RAW_DIR, ensure_dirs, read_jsonl, write_jsonl

_DATAMUSE_URL = "https://api.datamuse.com/words"
_DICTIONARY_URL = "https://api.dictionaryapi.dev/api/v2/entries/en/{word}"

# Polite default throttle. Both APIs tolerate faster, but this keeps the
# run well within implicit limits and is negligible for ~2000 words
# (1862 words * 0.2s * 2 APIs ≈ 12 minutes).
_DEFAULT_DELAY_SECONDS = 0.2


def _http_get_json(url: str, timeout: float) -> Any:
    """GET a JSON document. Returns ``None`` on any transport/parse failure.

    Network errors are part of normal operation for a dataset collector (a
    word may simply not exist in the dictionary); we treat them as "no data"
    rather than aborting the whole run.
    """

    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            # Some free APIs (notably dictionaryapi.dev) reject the default
            # urllib User-Agent; send a descriptive one so we look like a
            # legitimate client rather than an opaque library.
            "User-Agent": "LexiQuest-LM-dataset-collector/0.1 (research)",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:  # noqa: S310 - public API URL built from validated input
            if response.status != 200:
                return None
            raw = response.read()
    except (urllib.error.URLError, TimeoutError, OSError):
        return None
    try:
        return json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return None


def _first_example(payload: Any) -> str:
    """Pull the first non-empty example sentence from a dictionaryapi.dev payload."""

    if not isinstance(payload, list):
        return ""
    for entry in payload:
        if not isinstance(entry, dict):
            continue
        for meaning in entry.get("meanings", []) or []:
            if not isinstance(meaning, dict):
                continue
            for definition in meaning.get("definitions", []) or []:
                if not isinstance(definition, dict):
                    continue
                example = definition.get("example")
                if isinstance(example, str) and example.strip():
                    return example.strip()
    return ""


def _first_part_of_speech(payload: Any) -> str:
    """Pull the first part of speech from a dictionaryapi.dev payload."""

    if not isinstance(payload, list):
        return ""
    for entry in payload:
        if not isinstance(entry, dict):
            continue
        for meaning in entry.get("meanings", []) or []:
            if isinstance(meaning, dict):
                pos = meaning.get("partOfSpeech")
                if isinstance(pos, str) and pos.strip():
                    return pos.strip()
    return ""


def _datamuse_synonyms(word: str, timeout: float) -> list[str]:
    """Return up to 5 synonyms from Datamuse. Empty list on any failure."""

    params = urllib.parse.urlencode({"rel_syn": word, "max": 5})
    payload = _http_get_json(f"{_DATAMUSE_URL}?{params}", timeout)
    if not isinstance(payload, list):
        return []
    out: list[str] = []
    for item in payload:
        if isinstance(item, dict):
            candidate = item.get("word")
            if isinstance(candidate, str) and candidate.strip():
                out.append(candidate.strip())
    return out


def enrich_word(
    word: CefrWord,
    *,
    timeout: float,
    delay_seconds: float,
    sleep=time.sleep,
) -> CefrWord:
    """Return a new ``CefrWord`` with enriched fields where sources provided them.

    Never raises: a missing/failed source just means the field stays empty.
    Existing non-empty fields on the input are preserved (so the app seed
    bank's hand-written Thai meanings are never overwritten).
    """

    example = word.example_sentence
    pos = word.part_of_speech
    tags = word.tags

    dictionary_payload = _http_get_json(
        _DICTIONARY_URL.format(word=urllib.parse.quote(word.word)), timeout
    )
    sleep(delay_seconds)

    if not example:
        example = _first_example(dictionary_payload) or example
    if not pos:
        pos = _first_part_of_speech(dictionary_payload) or pos

    # Datamuse synonyms are folded into tags only when we have room (we cap at
    # 5 tags so the LM doesn't see a tag explosion). Skip if tags are already
    # populated (e.g. from the seed bank).
    if not tags:
        synonyms = _datamuse_synonyms(word.word, timeout)
        sleep(delay_seconds)
        tags = tuple(synonyms[:5])

    return CefrWord(
        word=word.word,
        cefr_level=word.cefr_level,
        meaning_th=word.meaning_th,  # Thai meaning comes from translate step, not here
        part_of_speech=pos,
        example_sentence=example,
        category=word.category,
        tags=tags,
        source="enriched",
    )


def enrich_words(
    words: Iterable[CefrWord],
    *,
    timeout: float,
    delay_seconds: float,
    progress=print,
) -> list[CefrWord]:
    """Enrich a stream of words, logging progress every 100 items."""

    out: list[CefrWord] = []
    for index, word in enumerate(words, start=1):
        out.append(enrich_word(word, timeout=timeout, delay_seconds=delay_seconds))
        if index % 100 == 0:
            progress(f"  enriched {index} words...", flush=True)
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Enrich words with definitions and examples from free dictionary APIs."
    )
    parser.add_argument(
        "--input",
        type=Path,
        default=RAW_DIR / "expanded_wordlist.jsonl",
        help="Input JSONL (default: expanded_wordlist.jsonl).",
    )
    parser.add_argument(
        "--seed",
        type=Path,
        default=RAW_DIR / "app_cefr_words.jsonl",
        help="Seed JSONL to merge in (its richer fields are preserved).",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=RAW_DIR / "enriched_words.jsonl",
        help="Output JSONL path.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Enrich only the first N words (0 = all). Useful for smoke tests.",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=_DEFAULT_DELAY_SECONDS,
        help="Delay between API calls in seconds (default: 0.2).",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=10.0,
        help="Per-request timeout in seconds (default: 10).",
    )
    args = parser.parse_args(argv)

    ensure_dirs()

    # Load seed first so its richer fields can be merged over the expanded
    # wordlist (the seed has hand-written Thai meanings + examples we want to
    # keep rather than overwrite with API data).
    seed_by_word: dict[str, CefrWord] = {}
    if args.seed.exists():
        for row in read_jsonl(args.seed):
            word = str(row.get("word", "")).strip().casefold()
            if word:
                seed_by_word[word] = _row_to_cefr_word(row)

    if not args.input.exists():
        print(f"ERROR: input file not found: {args.input}", file=sys.stderr)
        return 2

    inputs: list[CefrWord] = []
    for row in read_jsonl(args.input):
        word_str = str(row.get("word", "")).strip()
        if not word_str:
            continue
        candidate = _row_to_cefr_word(row)
        # Override with seed where the seed has data (seed wins on every field
        # it populated, because seed data is hand-curated and authoritative).
        seed = seed_by_word.get(candidate.word.casefold())
        if seed is not None:
            candidate = seed
        inputs.append(candidate)

    if args.limit > 0:
        inputs = inputs[: args.limit]

    total = len(inputs)
    print(
        f"Enriching {total} words (delay={args.delay}s)...",
        flush=True,
    )

    # Stream rows straight to disk so:
    #  - progress is visible (the file grows live, see `wc -l` from another
    #    shell),
    #  - a Ctrl-C or a machine crash keeps the partial dataset (we lose at
    #    most the in-flight row, not the whole run).
    ensure_dirs()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    filled_examples = 0
    count = 0
    with args.out.open("w", encoding="utf-8") as handle:
        for index, word in enumerate(inputs, start=1):
            enriched = enrich_word(
                word,
                timeout=args.timeout,
                delay_seconds=args.delay,
            )
            if enriched.example_sentence:
                filled_examples += 1
            handle.write(json.dumps(enriched.to_jsonl_dict(), ensure_ascii=False))
            handle.write("\n")
            count += 1
            # Flush periodically so progress is durable + observable.
            if index % 50 == 0:
                handle.flush()
                print(
                    f"  enriched {index}/{total} words "
                    f"({filled_examples} with example)",
                    flush=True,
                )

    print(
        f"Enriched {count} words; {filled_examples} have an example sentence.",
        flush=True,
    )
    print(f"Wrote {args.out}", flush=True)
    return 0


def _row_to_cefr_word(row: dict[str, object]) -> CefrWord:
    """Convert a JSONL row dict back to a ``CefrWord``."""

    tags_raw = row.get("tags") or []
    tags = tuple(str(t) for t in tags_raw) if isinstance(tags_raw, list) else ()
    return CefrWord(
        word=str(row.get("word", "")),
        cefr_level=str(row.get("cefr_level", "")),
        meaning_th=str(row.get("meaning_th", "")),
        part_of_speech=str(row.get("part_of_speech", "")),
        example_sentence=str(row.get("example_sentence", "")),
        category=str(row.get("category", "")),
        tags=tags,
        source=str(row.get("source", "")),
    )


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
