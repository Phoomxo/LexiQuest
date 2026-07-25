"""Tests for the evaluation harness (metric + report writer).

These cover the parts of ``evaluate.py`` that do not require torch: the
exact-match metric and the JSON report writer. The dry-run path of the
script itself is exercised by the smoke test in the dataset pipeline.
"""

from __future__ import annotations

import json
from pathlib import Path

from evaluate import StubModel, _exact_match_rate, _report


def test_exact_match_rate_handles_perfect_match() -> None:
    pairs = [("same", "same"), ("also same", "also same")]
    assert _exact_match_rate(pairs) == 1.0


def test_exact_match_rate_handles_no_matches() -> None:
    pairs = [("a", "b"), ("c", "d")]
    assert _exact_match_rate(pairs) == 0.0


def test_exact_match_rate_strips_whitespace() -> None:
    pairs = [("  padded  ", "padded")]
    assert _exact_match_rate(pairs) == 1.0


def test_exact_match_rate_empty_list_is_zero() -> None:
    assert _exact_match_rate([]) == 0.0


def test_report_writes_valid_json_with_all_fields(tmp_path: Path) -> None:
    out = tmp_path / "report.json"
    _report(
        checkpoint="test-ckpt",
        n_test=42,
        perplexity=12.5,
        exact_match=0.1,
        samples=[{"prompt": "p", "expected": "e", "predicted": "g"}],
        out_path=out,
    )

    assert out.exists()
    payload = json.loads(out.read_text(encoding="utf-8"))
    assert payload["checkpoint"] == "test-ckpt"
    assert payload["n_test_rows"] == 42
    assert payload["perplexity"] == 12.5
    assert payload["exact_match_rate"] == 0.1
    assert len(payload["samples"]) == 1


def test_report_accepts_none_perplexity_for_dry_run(tmp_path: Path) -> None:
    """Dry-run has no logits, so perplexity must be allowed to be None."""

    out = tmp_path / "dry.json"
    _report(
        checkpoint="dry",
        n_test=0,
        perplexity=None,
        exact_match=0.0,
        samples=[],
        out_path=out,
    )
    payload = json.loads(out.read_text(encoding="utf-8"))
    assert payload["perplexity"] is None


def test_stub_model_generate_is_deterministic() -> None:
    """The stub must return the same string for the same prompt every time,
    so dry-run evaluation reports are reproducible."""

    model = StubModel()
    a = model.generate("anything", max_new_tokens=8)
    b = model.generate("anything", max_new_tokens=8)
    assert a == b
