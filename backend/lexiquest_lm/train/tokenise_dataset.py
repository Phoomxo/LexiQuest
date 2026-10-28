"""Tokenise the instruction dataset for fine-tuning.

Reads ``data/processed/{train,validation,test}.jsonl`` (produced by
``merge_and_format.py``) and writes HuggingFace ``Dataset`` objects to
``data/tokenised/`` ready for ``lora_finetune.py``.

Instruction format
------------------
We use a ChatML-style prompt template compatible with Qwen2.5 so the
fine-tuned model can later be served with the same template:

    <|im_start|>system
    You are an English vocabulary teacher for Thai learners.<|im_end|>
    <|im_start|>user
    {prompt}<|im_end|>
    <|im_start|>assistant
    {response}<|im_end|>

Loss is computed only on the assistant response (the prompt tokens are masked
to -100), so the model learns to *generate* the answer rather than memorise
the question.

Dry-run
-------
``--dry-run`` tokenises a handful of rows using a stub tokeniser (no model
download) so the formatting + masking logic can be unit-tested without torch.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any, Iterable

from lexiquest_lm.dataset.io import PROCESSED_DIR, read_jsonl

# Directory for the tokenised arrow datasets. Lives under data/ so it is
# git-ignored (regenerable from the JSONL + tokeniser).
TOKENISED_DIR = PROCESSED_DIR.parent / "tokenised"

# The ChatML-style template Qwen2.5 uses. Hard-coded here so every run
# produces an identical prompt format (a thesis reproducibility requirement).
SYSTEM_PROMPT = "You are an English vocabulary teacher for Thai learners."

_PROMPT_TEMPLATE = (
    "<|im_start|>system\n{system}<|im_end|>\n"
    "<|im_start|>user\n{user}<|im_end|>\n"
    "<|im_start|>assistant\n"
)
_COMPLETION_TEMPLATE = "{response}<|im_end|>"
# Qwen2.5 uses <|im_end|> + newline as the eos token boundary.
_ASSISTANT_EOS = "<|im_end|>\n"


def format_prompt(user_prompt: str) -> str:
    """Return the formatted prompt portion (system + user + assistant header)."""

    return _PROMPT_TEMPLATE.format(system=SYSTEM_PROMPT, user=user_prompt)


def format_completion(response: str) -> str:
    """Return the formatted completion portion (assistant body + eos)."""

    return _COMPLETION_TEMPLATE.format(response=response) + _ASSISTANT_EOS


def full_text(user_prompt: str, response: str) -> str:
    """Return the full formatted sequence (prompt + completion)."""

    return format_prompt(user_prompt) + format_completion(response)


# ---------------------------------------------------------------------------
# Tokenisation
# ---------------------------------------------------------------------------


class StubTokenizer:
    """A whitespace-split stand-in used by ``--dry-run``.

    It mimics the slice of the HF tokenizer API we depend on (``encode`` +
    ``__call__`` returning ``input_ids``) so the masking logic can be tested
    without downloading Qwen2.5's ~1GB tokenizer.
    """

    def encode(self, text: str, add_special_tokens: bool = True) -> list[int]:  # noqa: ARG002
        # Map each whitespace token to a stable pseudo-id. The actual values
        # do not matter for the masking test; only the *lengths* do.
        return [abs(hash(tok)) % 100_000 for tok in text.split()] or [0]

    def __call__(
        self,
        text: str,
        *,
        truncation: bool = True,  # noqa: ARG002
        max_length: int = 1024,  # noqa: ARG002
        padding: str = "max_length",  # noqa: ARG002
        return_tensors: str = "pt",  # noqa: ARG002
    ) -> dict[str, list[int]]:
        ids = self.encode(text)
        # Pad/truncate deterministically so lengths are predictable.
        if len(ids) > max_length:
            ids = ids[:max_length]
        else:
            ids = ids + [0] * (max_length - len(ids))
        return {"input_ids": ids}

    @property
    def pad_token_id(self) -> int:
        return 0


def load_tokenizer(model_name: str, *, dry_run: bool):
    """Return a tokenizer for ``model_name``, or a stub in dry-run mode."""

    if dry_run:
        return StubTokenizer()
    from transformers import AutoTokenizer  # deferred so dry-run needs no torch

    tokenizer = AutoTokenizer.from_pretrained(model_name)
    if tokenizer.pad_token is None:
        # Qwen2.5 has no default pad token; reuse eos for padding.
        tokenizer.pad_token = tokenizer.eos_token
    return tokenizer


def build_example(
    row: dict[str, object],
    *,
    tokenizer,
    max_length: int,
) -> dict[str, int | list[int]]:
    """Tokenise one instruction row, masking the prompt out of the loss.

    Returns ``{"input_ids": [...], "labels": [...]}`` where ``labels`` is the
    full sequence with prompt positions set to -100 (ignored by the loss).
    """

    prompt = format_prompt(str(row.get("prompt", "")))
    completion = format_completion(str(row.get("response", "")))
    full = prompt + completion

    # Tokenise prompt and full separately so we know where the prompt ends.
    prompt_ids = tokenizer.encode(prompt, add_special_tokens=False)
    full_ids = tokenizer.encode(full, add_special_tokens=False)

    # Truncate from the left of the completion so the prompt + as much of the
    # completion as fits stay intact. For our short teaching examples this
    # rarely triggers, but it keeps very long stories from blowing the budget.
    if len(full_ids) > max_length:
        overflow = len(full_ids) - max_length
        full_ids = full_ids[: max(0, len(prompt_ids) - overflow)] + full_ids[
            len(prompt_ids):
        ]
        full_ids = full_ids[:max_length]
        prompt_len = max(0, len(prompt_ids) - overflow)
    else:
        prompt_len = len(prompt_ids)

    labels = list(full_ids)
    for i in range(min(prompt_len, len(labels))):
        labels[i] = -100

    return {"input_ids": full_ids, "labels": labels}


def tokenise_rows(
    rows: Iterable[dict[str, object]],
    *,
    tokenizer,
    max_length: int,
) -> list[dict[str, int | list[int]]]:
    out: list[dict[str, int | list[int]]] = []
    for row in rows:
        out.append(build_example(row, tokenizer=tokenizer, max_length=max_length))
    return out


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Tokenise the instruction dataset for fine-tuning."
    )
    parser.add_argument(
        "--model",
        default="Qwen/Qwen2.5-0.5B",
        help="Base model whose tokenizer to use (default: Qwen2.5-0.5B).",
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=PROCESSED_DIR,
        help="Directory containing train/validation/test.jsonl.",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=TOKENISED_DIR,
        help="Where to write the tokenised arrow datasets.",
    )
    parser.add_argument(
        "--max-length",
        type=int,
        default=512,
        help="Maximum sequence length (default: 512; teaching examples are short).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Use a stub tokenizer and skip model download; for testing the pipeline.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Tokenise only the first N rows per split (0 = all).",
    )
    args = parser.parse_args(argv)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    tokenizer = load_tokenizer(args.model, dry_run=args.dry_run)

    splits = ("train", "validation", "test")
    summary: dict[str, int] = {}
    for split in splits:
        path = args.data_dir / f"{split}.jsonl"
        if not path.exists():
            print(f"  skip {split}: {path} not found")
            continue
        rows = list(read_jsonl(path))
        if args.limit > 0:
            rows = rows[: args.limit]
        tokenised = tokenise_rows(
            rows, tokenizer=tokenizer, max_length=args.max_length
        )
        summary[split] = len(tokenised)

        if args.dry_run:
            # In dry-run we only print; writing arrow datasets would require
            # the datasets library, which dry-run deliberately avoids.
            print(
                f"  {split}: would tokenise {len(tokenised)} rows "
                f"(dry-run, stub tokenizer)"
            )
            if tokenised:
                ex = tokenised[0]
                print(
                    f"    example lengths: input_ids={len(ex['input_ids'])}, "
                    f"masked_labels={sum(1 for l in ex['labels'] if l == -100)}"
                )
        else:
            from datasets import Dataset  # deferred; only needed for real run

            Dataset.from_list(tokenised).save_to_disk(str(args.out_dir / split))
            print(f"  {split}: tokenised {len(tokenised)} rows -> {args.out_dir / split}")

    print("Tokenise summary:", summary)
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
