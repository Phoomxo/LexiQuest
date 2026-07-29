"""Collector: parse the app's CEFR word bank out of the Dart source.

The Flutter app holds its seed vocabulary as a ``const List<CefrWord>`` in
``lib/services/cefr_service.dart``. This collector parses that source file
(without executing Dart) so the LM dataset starts from exactly the words the
app teaches — guaranteeing dataset/app alignment by construction.

Parsing approach: a small regex-based scanner is enough because the file is
machine-generated-style ``CefrWord(...)`` literals. We deliberately do not
attempt a full Dart parser; if the source format changes, this collector
should fail loudly rather than silently drop words.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from lexiquest_lm.dataset.io import CefrWord, RAW_DIR, ensure_dirs, write_jsonl

# Resolve the app source relative to this backend so the collector works from
# any CWD. ``collect_cefr_words.py`` lives at
# ``backend/lexiquest_lm/dataset/collect_cefr_words.py`` and the repo root is
# five levels above it: dataset -> lexiquest_lm -> backend -> repo root.
_REPO_ROOT = Path(__file__).resolve().parents[3]
_APP_CEFR_SOURCE = _REPO_ROOT / "lib" / "services" / "cefr_service.dart"

# Each field inside a CefrWord literal is matched by its own regex. Running
# one pattern per field (rather than one big alternation) avoids the
# ``finditer`` group-index ambiguity that previously dropped fields when two
# alternatives could match the same span.
_FIELD_PATTERNS: dict[str, re.Pattern[str]] = {
    "word": re.compile(r"word:\s*'([^']*)'"),
    "cefr": re.compile(r"cefrLevel:\s*'([^']*)'"),
    "category": re.compile(r"category:\s*'([^']*)'"),
    "meaning": re.compile(r"meaning:\s*'([^']*)'"),
    "pos": re.compile(r"partOfSpeech:\s*'([^']*)'"),
    "example": re.compile(r"exampleSentence:\s*'([^']*)'"),
    "tags": re.compile(r"tags:\s*\[([^\]]*)\]"),
}
_BLOCK_HEADER_RE = re.compile(r"CefrWord\(\s*")


def _parse_tag_list(raw: str) -> tuple[str, ...]:
    """Parse the inside of a ``tags: [...]`` literal into a tuple of strings."""

    if not raw.strip():
        return ()
    # Tags look like: 'daily', 'toeic' — split on commas, strip quotes/space.
    parts = [p.strip().strip("'\"") for p in raw.split(",")]
    return tuple(p for p in parts if p)


def parse_cefr_source(source: str) -> list[CefrWord]:
    """Parse the Dart source text of ``cefr_service.dart`` into CefrWord records.

    Raises ``ValueError`` if zero words are found, because that almost always
    means the source format changed and the regex silently matched nothing.
    """

    records: list[CefrWord] = []
    # Find each ``CefrWord(`` start, then scan forward to the matching ``)``.
    for match in _BLOCK_HEADER_RE.finditer(source):
        start = match.end()
        depth = 1
        end = start
        while end < len(source) and depth > 0:
            char = source[end]
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
            end += 1
        block = source[start : end - 1]

        fields: dict[str, str] = {}
        for name, pattern in _FIELD_PATTERNS.items():
            m = pattern.search(block)
            if m is not None:
                fields[name] = m.group(1)

        word = fields.get("word", "").strip()
        if not word:
            continue

        records.append(
            CefrWord(
                word=word,
                cefr_level=fields.get("cefr", "").strip(),
                meaning_th=fields.get("meaning", "").strip(),
                part_of_speech=fields.get("pos", "").strip(),
                example_sentence=fields.get("example", "").strip(),
                category=fields.get("category", "").strip(),
                tags=_parse_tag_list(fields.get("tags", "")),
                source="app_cefr_bank",
            )
        )

    if not records:
        raise ValueError(
            "No CefrWord entries parsed from source. The Dart source format "
            "may have changed; update the regex in collect_cefr_words.py."
        )
    return records


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Parse the app's CEFR word bank into a raw JSONL dataset."
    )
    parser.add_argument(
        "--source",
        type=Path,
        default=_APP_CEFR_SOURCE,
        help="Path to cefr_service.dart (default: the app source in this repo).",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=RAW_DIR / "app_cefr_words.jsonl",
        help="Output JSONL path.",
    )
    args = parser.parse_args(argv)

    ensure_dirs()
    if not args.source.exists():
        print(f"ERROR: source file not found: {args.source}", file=sys.stderr)
        return 2

    source_text = args.source.read_text(encoding="utf-8")
    records = parse_cefr_source(source_text)
    count = write_jsonl(args.out, (r.to_jsonl_dict() for r in records))

    print(f"Parsed {count} CefrWord entries from {args.source}")
    print(f"Wrote {args.out}")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
