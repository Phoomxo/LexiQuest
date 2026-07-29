"""Collector: merge all raw datasets into one instruction-tuning JSONL.

This is the **fan-in** of the pipeline. It reads every ``data/raw/*.jsonl``
produced by the other collectors, normalises them to a single instruction
shape, deduplicates, shuffles deterministically, and writes the final training
file plus train/val/test splits.

Output files (under ``data/processed/``):

* ``train.jsonl``, ``validation.jsonl``, ``test.jsonl`` — the splits, written
  in the same instruction shape so the trainer loads them directly.
* ``manifest.json`` — provenance: row counts per source, per kind, per split,
  so the thesis can cite exact dataset composition.

Design notes:

* The merge is order-independent: any subset of raw files may be present (e.g.
  Tatoeba skipped because ``datasets`` is not installed) and the merge still
  produces a valid dataset from whatever is there.
* Deduplication is on the ``(prompt, response)`` pair, not on response alone,
  because the same response can legitimately appear under two prompts.
* Splits are stratified by ``kind`` so train/val/test each see the same
  sentence/story/explanation mix (otherwise test might end up all stories).
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from collections import defaultdict
from pathlib import Path
from typing import Iterable

from lexiquest_lm.dataset.io import (
    PROCESSED_DIR,
    RAW_DIR,
    ensure_dirs,
    read_jsonl,
    write_jsonl,
)

# Each raw file is a list of dicts; we only care about a few fields. Unknown
# files (no recognised shape) are skipped with a warning rather than aborting
# the whole merge, so adding a new collector never blocks the pipeline.
_DEFAULT_INPUTS = [
    RAW_DIR / "synthetic_examples.jsonl",
    RAW_DIR / "tatoeba_sentences.jsonl",
]

# Fields preserved in the final dataset. Anything else is dropped so the
# trainer sees a stable, narrow schema.
_OUTPUT_FIELDS = ("prompt", "response", "kind", "cefr", "word", "source")


def _load_rows(path: Path) -> list[dict[str, object]]:
    """Load a raw JSONL file, keeping only the fields the trainer needs.

    Returns an empty list if the file does not exist or has no recognised
    ``prompt``/``response`` fields.
    """

    if not path.exists():
        return []
    out: list[dict[str, object]] = []
    for row in read_jsonl(path):
        prompt = row.get("prompt")
        response = row.get("response")
        if not isinstance(prompt, str) or not isinstance(response, str):
            continue
        if not prompt.strip() or not response.strip():
            continue
        normalised = {field: row.get(field, "") for field in _OUTPUT_FIELDS}
        normalised["prompt"] = prompt.strip()
        normalised["response"] = response.strip()
        out.append(normalised)
    return out


def _dedupe(rows: Iterable[dict[str, object]]) -> list[dict[str, object]]:
    """Drop rows with identical (prompt, response). First occurrence wins."""

    seen: set[tuple[str, str]] = set()
    out: list[dict[str, object]] = []
    for row in rows:
        key = (str(row["prompt"]), str(row["response"]))
        if key in seen:
            continue
        seen.add(key)
        out.append(row)
    return out


def _stratified_split(
    rows: list[dict[str, object]],
    *,
    val_fraction: float,
    test_fraction: float,
    rng: random.Random,
) -> tuple[list[dict[str, object]], list[dict[str, object]], list[dict[str, object]]]:
    """Split rows into train/validation/test, stratified by ``kind``.

    Stratification keeps the kind distribution identical across splits, which
    matters because the model is evaluated on the same mix it trains on.
    """

    by_kind: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in rows:
        by_kind[str(row.get("kind", ""))].append(row)

    train: list[dict[str, object]] = []
    val: list[dict[str, object]] = []
    test: list[dict[str, object]] = []
    for kind_rows in by_kind.values():
        rng.shuffle(kind_rows)
        n = len(kind_rows)
        n_test = int(n * test_fraction)
        n_val = int(n * val_fraction)
        test.extend(kind_rows[:n_test])
        val.extend(kind_rows[n_test : n_test + n_val])
        train.extend(kind_rows[n_test + n_val :])
    rng.shuffle(train)
    rng.shuffle(val)
    rng.shuffle(test)
    return train, val, test


def _build_manifest(
    *,
    train: list[dict[str, object]],
    val: list[dict[str, object]],
    test: list[dict[str, object]],
) -> dict[str, object]:
    """Return a provenance manifest summarising the merged dataset."""

    def _by(rows: list[dict[str, object]], field: str) -> dict[str, int]:
        counts: dict[str, int] = defaultdict(int)
        for row in rows:
            counts[str(row.get(field, ""))] += 1
        return dict(sorted(counts.items()))

    return {
        "total_rows": len(train) + len(val) + len(test),
        "splits": {
            "train": len(train),
            "validation": len(val),
            "test": len(test),
        },
        "by_kind": {
            "train": _by(train, "kind"),
            "validation": _by(val, "kind"),
            "test": _by(test, "kind"),
        },
        "by_source": {
            "train": _by(train, "source"),
            "validation": _by(val, "source"),
            "test": _by(test, "source"),
        },
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Merge raw datasets into train/val/test instruction JSONL."
    )
    parser.add_argument(
        "--inputs",
        type=Path,
        nargs="+",
        default=_DEFAULT_INPUTS,
        help="Raw JSONL files to merge (default: synthetic + tatoeba).",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=PROCESSED_DIR,
        help="Output directory for train/val/test/manifest.",
    )
    parser.add_argument(
        "--val-fraction",
        type=float,
        default=0.1,
        help="Validation fraction per kind (default: 0.1).",
    )
    parser.add_argument(
        "--test-fraction",
        type=float,
        default=0.1,
        help="Test fraction per kind (default: 0.1).",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for deterministic shuffling/splitting (default: 42).",
    )
    args = parser.parse_args(argv)

    if not 0.0 <= args.val_fraction < 1.0:
        print("ERROR: --val-fraction out of range", file=sys.stderr)
        return 2
    if not 0.0 <= args.test_fraction < 1.0:
        print("ERROR: --test-fraction out of range", file=sys.stderr)
        return 2
    if args.val_fraction + args.test_fraction >= 1.0:
        print("ERROR: val + test fractions must be < 1.0", file=sys.stderr)
        return 2

    ensure_dirs()
    args.out_dir.mkdir(parents=True, exist_ok=True)

    all_rows: list[dict[str, object]] = []
    for path in args.inputs:
        rows = _load_rows(path)
        print(f"  loaded {len(rows):>6} rows from {path.name}")
        all_rows.extend(rows)

    if not all_rows:
        print("ERROR: no rows loaded from any input", file=sys.stderr)
        return 2

    before = len(all_rows)
    all_rows = _dedupe(all_rows)
    print(f"  deduped {before} -> {len(all_rows)} rows")

    rng = random.Random(args.seed)
    train, val, test = _stratified_split(
        all_rows,
        val_fraction=args.val_fraction,
        test_fraction=args.test_fraction,
        rng=rng,
    )

    train_path = args.out_dir / "train.jsonl"
    val_path = args.out_dir / "validation.jsonl"
    test_path = args.out_dir / "test.jsonl"
    write_jsonl(train_path, train)
    write_jsonl(val_path, val)
    write_jsonl(test_path, test)

    manifest = _build_manifest(train=train, val=val, test=test)
    manifest_path = args.out_dir / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    print(
        f"Wrote train={len(train)}, validation={len(val)}, test={len(test)} "
        f"(total {manifest['total_rows']})"
    )
    print(f"Splits + manifest in {args.out_dir}")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
