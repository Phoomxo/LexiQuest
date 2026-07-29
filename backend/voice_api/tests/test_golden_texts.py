import json
from pathlib import Path

RESEARCH_DIR = Path(__file__).parent.parent / "research"
GOLDEN_SET_PATH = RESEARCH_DIR / "golden_texts.json"


def test_golden_set_file_exists_and_valid() -> None:
    assert GOLDEN_SET_PATH.exists()

    with GOLDEN_SET_PATH.open("r", encoding="utf-8") as f:
        data = json.load(f)

    assert isinstance(data, list)
    assert len(data) >= 4

    seen_ids = set()
    for item in data:
        assert "id" in item
        assert item["id"] not in seen_ids
        seen_ids.add(item["id"])

        assert "text" in item and len(item["text"].strip()) > 0
        assert item["language"] in ("en", "th")
        assert "category" in item
