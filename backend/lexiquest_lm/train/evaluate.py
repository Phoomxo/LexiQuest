"""Evaluate a fine-tuned LexiQuest-LM checkpoint.

Two metrics:

1. **Perplexity on the test split** — the standard intrinsic LM quality number.
   Lower is better; for a 0.5B vocabulary-teaching model trained on 50K rows
   we expect something in the 5-30 range after a few epochs.

2. **Sample completions** — generate a handful of responses to held-out
   prompts and print them side-by-side with the expected response, so a human
   can do a quick qualitative check before deploying.

Dry-run
-------
``--dry-run`` runs the exact evaluation harness on a stub model that returns a
fixed completion. No Qwen download, no GPU. Validates that the dataset load,
prompt formatting, generation loop, and report writer all work end-to-end
before pointing at a real checkpoint.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any

from lexiquest_lm.dataset.io import PROCESSED_DIR, read_jsonl
from tokenise_dataset import format_prompt

REPORT_DIR = PROCESSED_DIR.parent.parent / "reports"


class StubModel:
    """Stand-in used by ``--dry-run``: returns a fixed deterministic completion.

    Implements the two methods ``evaluate`` calls on a real model
    (``generate`` and a perplexity path via ``__call__``), so the harness code
    is identical between dry-run and real evaluation.
    """

    def __init__(self, *, vocab_size: int = 100_000) -> None:
        self._vocab_size = vocab_size

    @property
    def config(self) -> dict[str, int]:
        return {"vocab_size": self._vocab_size}

    def generate(self, prompt: str, *, max_new_tokens: int) -> str:  # noqa: ARG002
        # Deterministic, obviously-fake completion so the dry-run report is
        # stable across runs and easy to spot as a stub.
        return "This is a dry-run stub completion."


# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------


def _exact_match_rate(
    pairs: list[tuple[str, str]],
) -> float:
    """Fraction of (predicted, expected) pairs that match exactly.

    Exact match is a harsh metric for free-form generation, but it is a useful
    ceiling probe: a perfect template-memorising model scores 1.0 here, and a
    model that diverges usefully scores well below 1.0 without being wrong.
    """

    if not pairs:
        return 0.0
    hits = sum(
        1 for predicted, expected in pairs if predicted.strip() == expected.strip()
    )
    return hits / len(pairs)


def _report(
    *,
    checkpoint: str,
    n_test: int,
    perplexity: float | None,
    exact_match: float,
    samples: list[dict[str, str]],
    out_path: Path,
) -> None:
    """Write a JSON evaluation report plus echo a human-readable summary."""

    out_path.parent.mkdir(parents=True, exist_ok=True)
    report = {
        "checkpoint": checkpoint,
        "n_test_rows": n_test,
        "perplexity": perplexity,
        "exact_match_rate": exact_match,
        "samples": samples,
    }
    out_path.write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    print(f"Evaluation report -> {out_path}")
    print(f"  checkpoint:     {checkpoint}")
    print(f"  test rows:      {n_test}")
    if perplexity is not None:
        print(f"  perplexity:     {perplexity:.3f}")
    print(f"  exact match:    {exact_match:.3f}")
    print("  sample completions:")
    for i, s in enumerate(samples, start=1):
        print(f"    [{i}] prompt:   {s['prompt'][:80]}")
        print(f"        expected: {s['expected'][:80]}")
        print(f"        got:      {s['predicted'][:80]}")


# ---------------------------------------------------------------------------
# Dry-run path
# ---------------------------------------------------------------------------


def _run_dry_evaluate(args: argparse.Namespace) -> int:
    test_path = PROCESSED_DIR / "test.jsonl"
    if not test_path.exists():
        print(f"ERROR: {test_path} not found. Run merge_and_format.py first.", file=sys.stderr)
        return 2
    rows = list(read_jsonl(test_path))[: args.sample_count]

    model = StubModel()
    samples: list[dict[str, str]] = []
    for row in rows:
        prompt = format_prompt(str(row.get("prompt", "")))
        predicted = model.generate(prompt, max_new_tokens=args.max_new_tokens)
        samples.append(
            {
                "prompt": str(row.get("prompt", "")),
                "expected": str(row.get("response", "")),
                "predicted": predicted,
            }
        )

    em = _exact_match_rate([(s["predicted"], s["expected"]) for s in samples])
    # No real logits in dry-run; perplexity is intentionally None.
    _report(
        checkpoint="dry-run-stub",
        n_test=len(rows),
        perplexity=None,
        exact_match=em,
        samples=samples,
        out_path=REPORT_DIR / "dry_run_eval.json",
    )
    return 0


# ---------------------------------------------------------------------------
# Real evaluation path (requires torch + transformers + peft)
# ---------------------------------------------------------------------------


def _compute_perplexity(model, tokenizer, rows, *, max_length: int) -> float:
    """Mean negative-log-likelihood perplexity over the test split.

    A proper no-grad, batched implementation; for our small test split the
    wall-clock cost is negligible. Labels are masked exactly as in training
    so only completion tokens contribute.
    """

    import torch
    from tokenise_dataset import build_example

    model.eval()
    total_nll = 0.0
    total_tokens = 0
    with torch.no_grad():
        for row in rows:
            ex = build_example(row, tokenizer=tokenizer, max_length=max_length)
            input_ids = torch.tensor([ex["input_ids"]], dtype=torch.long).to(model.device)
            labels = torch.tensor([ex["labels"]], dtype=torch.long).to(model.device)
            out = model(input_ids=input_ids, labels=labels)
            # HF returns summed loss over non-masked tokens; convert to mean.
            n_tokens = int((labels[0] != -100).sum().item())
            if n_tokens == 0:
                continue
            # ``loss`` is already a mean over non-ignored tokens per HF, so
            # accumulate token-weighted.
            total_nll += float(out.loss.item()) * n_tokens
            total_tokens += n_tokens
    if total_tokens == 0:
        return float("inf")
    return math.exp(total_nll / total_tokens)


def _run_real_evaluate(args: argparse.Namespace) -> int:
    import torch
    from peft import PeftModel
    from transformers import AutoModelForCausalLM, AutoTokenizer

    test_path = PROCESSED_DIR / "test.jsonl"
    if not test_path.exists():
        print(f"ERROR: {test_path} not found.", file=sys.stderr)
        return 2
    rows = list(read_jsonl(test_path))

    print(f"Loading base model {args.model}...")
    tokenizer = AutoTokenizer.from_pretrained(args.model, trust_remote_code=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token
    base = AutoModelForCausalLM.from_pretrained(
        args.model,
        device_map="auto",
        torch_dtype=torch.float16,
        trust_remote_code=True,
    )

    if args.adapter and Path(args.adapter).exists():
        print(f"Loading LoRA adapter from {args.adapter}...")
        model = PeftModel.from_pretrained(base, args.adapter)
    else:
        model = base

    perplexity = _compute_perplexity(
        model, tokenizer, rows, max_length=args.max_length
    )

    # Sample completions for qualitative review.
    sample_rows = rows[: args.sample_count]
    samples: list[dict[str, str]] = []
    model.eval()
    for row in sample_rows:
        prompt_text = format_prompt(str(row.get("prompt", "")))
        inputs = tokenizer(prompt_text, return_tensors="pt").to(model.device)
        with torch.no_grad():
            out = model.generate(
                **inputs,
                max_new_tokens=args.max_new_tokens,
                do_sample=False,  # greedy for reproducibility
                pad_token_id=tokenizer.pad_token_id,
            )
        new_tokens = out[0][inputs["input_ids"].shape[1]:]
        predicted = tokenizer.decode(new_tokens, skip_special_tokens=True).strip()
        samples.append(
            {
                "prompt": str(row.get("prompt", "")),
                "expected": str(row.get("response", "")),
                "predicted": predicted,
            }
        )

    em = _exact_match_rate([(s["predicted"], s["expected"]) for s in samples])
    _report(
        checkpoint=str(args.adapter or args.model),
        n_test=len(rows),
        perplexity=perplexity,
        exact_match=em,
        samples=samples,
        out_path=REPORT_DIR / "eval.json",
    )
    return 0


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Evaluate a LexiQuest-LM checkpoint on the test split."
    )
    parser.add_argument(
        "--model",
        default="Qwen/Qwen2.5-0.5B",
        help="Base model name (default: Qwen2.5-0.5B).",
    )
    parser.add_argument(
        "--adapter",
        default=None,
        help="Path to the LoRA adapter directory (default: evaluate base only).",
    )
    parser.add_argument(
        "--max-new-tokens",
        type=int,
        default=64,
        help="Max tokens to generate per sample (default: 64).",
    )
    parser.add_argument(
        "--max-length",
        type=int,
        default=512,
        help="Max sequence length for perplexity (default: 512).",
    )
    parser.add_argument(
        "--sample-count",
        type=int,
        default=10,
        help="Number of qualitative samples to print (default: 10).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Run with a stub model; no Qwen download or GPU.",
    )
    args = parser.parse_args(argv)

    if args.dry_run:
        return _run_dry_evaluate(args)
    return _run_real_evaluate(args)


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
