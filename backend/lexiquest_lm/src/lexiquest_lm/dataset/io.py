"""Shared helpers for the dataset collection pipeline.

Centralises:

* path resolution (``data/raw`` and ``data/processed`` under this backend),
* JSONL read/write (the lingua franca between collectors and the formatter),
* a normalised ``CefrWord`` record every collector converges to, so the
  formatter never has to special-case a source.

Keeping these helpers tiny and dependency-free means every collector can be
run on a fresh checkout without torch/transformers installed.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Iterable, Iterator

# Resolve paths deterministically relative to this module so collectors work
# regardless of the process working directory. ``io.py`` lives four levels
# below the backend project root (src/lexiquest_lm/dataset/io.py).
_BACKEND_ROOT = Path(__file__).resolve().parent.parent.parent.parent
DATA_DIR = _BACKEND_ROOT / "data"
RAW_DIR = DATA_DIR / "raw"
PROCESSED_DIR = DATA_DIR / "processed"


@dataclass(frozen=True, slots=True)
class CefrWord:
    """Normalised vocabulary record used across all collectors.

    Every source (app CEFR bank, dictionary API, synthetic generator, public
    datasets) is mapped to this shape before being written to disk, so the
    formatter downstream has exactly one input type to handle.
    """

    word: str
    cefr_level: str  # A1, A2, B1, B2, C1, C2, or "" when unknown
    meaning_th: str = ""
    part_of_speech: str = ""
    example_sentence: str = ""
    category: str = ""
    tags: tuple[str, ...] = field(default_factory=tuple)
    source: str = ""  # which collector produced this row, for provenance

    def to_jsonl_dict(self) -> dict[str, object]:
        d = asdict(self)
        # Tuples are not JSON-native; serialise as lists.
        d["tags"] = list(self.tags)
        return d


def ensure_dirs() -> None:
    """Create the raw/processed data directories if they do not exist."""

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)


def write_jsonl(path: Path, rows: Iterable[dict[str, object]]) -> int:
    """Write rows to ``path`` as JSON Lines. Returns the number of rows written.

    Truncates the file first so re-runs are idempotent (a collector re-run
    fully replaces its output rather than appending duplicates).
    """

    ensure_dirs()
    count = 0
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False))
            handle.write("\n")
            count += 1
    return count


def read_jsonl(path: Path) -> Iterator[dict[str, object]]:
    """Yield each row of a JSONL file as a dict. Skips blank lines."""

    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            yield json.loads(line)
