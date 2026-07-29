"""LoRA fine-tune Qwen2.5-0.5B on the LexiQuest instruction dataset.

This is the heart of Phase B. It loads the base model with 4-bit quantisation
(so the 0.5B model + LoRA adapters fit comfortably in the 8GB RTX 3050),
attaches LoRA adapters, and runs a short supervised fine-tune over the
tokenised dataset.

Two run modes
-------------
- ``--dry-run``: builds a 2-layer toy model from scratch and runs every step
  of the training loop on a handful of tokenised rows. No Qwen download, no
  GPU required. Validates that the dataset -> tokeniser -> masking -> forward
  -> backward -> save chain works end-to-end before committing GPU time.
- ``--train`` (default behaviour without ``--dry-run``): loads the real
  Qwen2.5-0.5B, applies LoRA, fine-tunes, and saves the merged adapter to
  ``checkpoints/``.

Hardware notes
--------------
Defaults target the workstation RTX 3050 (8GB VRAM):

- batch size 1 + gradient accumulation 8 (effective batch 8)
- 4-bit NF4 quantisation via bitsandbytes
- LoRA rank 16, alpha 32, dropout 0.05 (the standard Qwen LoRA recipe)
- ~3 epochs over the 50K-row dataset ≈ 2-4 hours wall clock

Override any of these via CLI for a different GPU.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from lexiquest_lm.dataset.io import PROCESSED_DIR

CHECKPOINT_DIR = PROCESSED_DIR.parent.parent / "checkpoints"
TOKENISED_DIR = PROCESSED_DIR.parent / "tokenised"


# ---------------------------------------------------------------------------
# Toy model used by --dry-run so the full loop runs without torch/CUDA.
# ---------------------------------------------------------------------------


def _build_tiny_model(vocab_size: int, max_length: int):
    """Construct a 2-layer transformer-ish model purely for loop validation.

    Lives inside this function so the import is deferred to the real training
    path only; the dry-run path uses a pure-Python stand-in (see
    ``_run_dry_train``) so it needs no torch.
    """

    import torch
    import torch.nn as nn

    class TinyLM(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.embed = nn.Embedding(vocab_size, 32)
            self.fc1 = nn.Linear(32, 32)
            self.fc2 = nn.Linear(32, vocab_size)

        def forward(self, input_ids, labels=None):
            x = self.embed(input_ids)
            x = torch.relu(self.fc1(x))
            logits = self.fc2(x)
            loss = None
            if labels is not None:
                # Standard causal-LM shift; -100 labels are ignored.
                shift_logits = logits[..., :-1, :].contiguous()
                shift_labels = labels[..., 1:].contiguous()
                loss = nn.functional.cross_entropy(
                    shift_logits.view(-1, shift_logits.size(-1)),
                    shift_labels.view(-1),
                    ignore_index=-100,
                )
            return {"loss": loss, "logits": logits}

    return TinyLM()


def _run_dry_train(args: argparse.Namespace) -> int:
    """Validate the training loop end-to-end WITHOUT torch.

    Dry-run must run on a machine that has only the dataset-collection
    dependencies (no torch/transformers/peft/bitsandbytes). So we simulate
    the loop in pure Python:

    - Re-use ``tokenise_dataset.build_example`` so the masking logic exercised
      here is the *exact same* code path as the real run.
    - Replace the model with a tiny bag-of-tokens linear classifier trained
      with manual SGD. The point is not to learn anything meaningful — it is
      to prove the dataset -> masking -> forward -> loss -> backward ->
      step -> checkpoint chain runs end-to-end before committing GPU time.

    A real ``torch``-based toy model is available via ``_build_tiny_model``
    but is intentionally NOT used here so dry-run stays dependency-free.
    """

    import math
    import random

    from tokenise_dataset import StubTokenizer, build_example
    from lexiquest_lm.dataset.io import read_jsonl

    tokenizer = StubTokenizer()
    rows = list(read_jsonl(PROCESSED_DIR / "train.jsonl"))[: args.dry_run_rows]
    if not rows:
        print("ERROR: no training rows found at data/processed/train.jsonl", file=sys.stderr)
        print("Run merge_and_format.py first.", file=sys.stderr)
        return 2

    examples = [
        build_example(row, tokenizer=tokenizer, max_length=args.max_length)
        for row in rows
    ]

    # Pure-Python "model": a weight vector over a hashed feature space.
    # Each non-masked token id hashes to a feature; we predict whether the
    # example's response is "long" (>median). The task is arbitrary — we only
    # need a real loss + gradient + update to exercise the loop.
    feature_dim = 1024
    rng = random.Random(0)
    weights = [rng.gauss(0, 0.1) for _ in range(feature_dim)]
    bias = 0.0

    def _featurise(ex: dict) -> list[int]:
        feats: list[int] = []
        for tok in ex["input_ids"]:
            if ex["labels"][min(len(feats), len(ex["labels"]) - 1)] == -100:
                continue  # skip masked (prompt) positions
            feats.append(tok % feature_dim)
        return feats or [0]

    featurised = [_featurise(ex) for ex in examples]
    lengths = [len(ex["input_ids"]) for ex in examples]
    median_len = sorted(lengths)[len(lengths) // 2] if lengths else 0
    labels = [1.0 if len(ex["input_ids"]) > median_len else 0.0 for ex in examples]

    print(
        f"Dry-run training (pure-Python logistic regression) on {len(examples)} "
        f"examples for {args.epochs} epoch(s)..."
    )
    lr = args.learning_rate
    for epoch in range(args.epochs):
        total_loss = 0.0
        correct = 0
        for feats, label in zip(featurised, labels, strict=True):
            logit = bias + sum(weights[f] for f in feats)
            # BCE with logits, numerically stable.
            if logit >= 0:
                loss = logit * (1 - label) + math.log1p(math.exp(-logit))
                pred = 1.0
            else:
                loss = -logit * label + math.log1p(math.exp(logit))
                pred = 0.0 if logit < 0 else 1.0
            grad = 1.0 / (1.0 + math.exp(-logit)) - label  # d loss / d logit
            for f in feats:
                weights[f] -= lr * grad
            bias -= lr * grad
            total_loss += loss
            correct += int(pred == label)
        avg = total_loss / max(1, len(examples))
        acc = correct / max(1, len(examples))
        print(
            f"  epoch {epoch + 1}/{args.epochs}  avg_loss={avg:.4f}  acc={acc:.2f}"
        )

    # Persist a marker so downstream tooling can detect a successful dry-run.
    CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)
    (CHECKPOINT_DIR / "DRY_RUN_OK").write_text(
        f"dry-run completed: {len(examples)} examples, {args.epochs} epoch(s), "
        f"final_acc={acc:.2f}\n",
        encoding="utf-8",
    )
    print(f"Dry-run OK. Marker written to {CHECKPOINT_DIR / 'DRY_RUN_OK'}")
    return 0


# ---------------------------------------------------------------------------
# Real training path (requires torch + transformers + peft + bitsandbytes).
# ---------------------------------------------------------------------------


def _run_real_train(args: argparse.Namespace) -> int:
    """Fine-tune Qwen2.5-0.5B with LoRA on the real tokenised dataset.

    Imports are deferred to this function so ``--dry-run`` never requires
    torch/transformers/peft/bitsandbytes.
    """

    import torch
    from datasets import load_from_disk
    from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training
    from transformers import (
        AutoModelForCausalLM,
        AutoTokenizer,
        BitsAndBytesConfig,
        DataCollatorForSeq2Seq,
        TrainingArguments,
        Trainer,
    )

    from tokenise_dataset import TOKENISED_DIR, load_tokenizer, tokenise_rows
    from lexiquest_lm.dataset.io import read_jsonl

    # ---- Base model, 4-bit quantised with FP16 fallback ----
    tokenizer = AutoTokenizer.from_pretrained(args.model)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    try:
        bnb_config = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_compute_dtype=torch.float16,
            bnb_4bit_use_double_quant=True,
        )
        print(f"Loading base model {args.model} (4-bit quantised)...")
        model = AutoModelForCausalLM.from_pretrained(
            args.model,
            quantization_config=bnb_config,
            device_map="auto",
        )
        model = prepare_model_for_kbit_training(model)
    except Exception as err:
        print(f"BitsAndBytes 4-bit quantization unavailable ({err}).")
        print(f"Falling back to native FP16 precision (0.5B model fits comfortably in VRAM)...")
        model = AutoModelForCausalLM.from_pretrained(
            args.model,
            dtype=torch.float16,
            device_map="auto",
        )

    # ---- LoRA adapters ----
    lora_config = LoraConfig(
        r=args.lora_rank,
        lora_alpha=args.lora_alpha,
        lora_dropout=args.lora_dropout,
        bias="none",
        task_type="CAUSAL_LM",
        # Target Qwen2.5's attention + MLP projections; this is the standard
        # recipe that yields good instruction-following at rank 16.
        target_modules=[
            "q_proj",
            "k_proj",
            "v_proj",
            "o_proj",
            "gate_proj",
            "up_proj",
            "down_proj",
        ],
    )
    model = get_peft_model(model, lora_config)
    model.print_trainable_parameters()

    # ---- Tokenise splits on the fly (so we don't depend on a prior run) ----
    def _tokenise_split(split: str):
        path = PROCESSED_DIR / f"{split}.jsonl"
        rows = list(read_jsonl(path))
        examples = tokenise_rows(
            rows, tokenizer=tokenizer, max_length=args.max_length
        )
        from datasets import Dataset

        return Dataset.from_list(examples)

    train_ds = _tokenise_split("train")
    eval_ds = _tokenise_split("validation")

    if args.max_train_rows > 0:
        train_ds = train_ds.select(range(min(args.max_train_rows, len(train_ds))))
        eval_ds = eval_ds.select(range(min(max(1, args.max_train_rows // 10), len(eval_ds))))
        print(f"Smoke test: capped train={len(train_ds)}, eval={len(eval_ds)}")

    # ---- Trainer ----
    training_args = TrainingArguments(
        output_dir=str(CHECKPOINT_DIR),
        num_train_epochs=args.epochs,
        per_device_train_batch_size=args.batch_size,
        gradient_accumulation_steps=args.gradient_accumulation,
        learning_rate=args.learning_rate,
        warmup_ratio=0.03,
        lr_scheduler_type="cosine",
        logging_steps=20,
        eval_strategy="epoch",
        save_strategy="epoch",
        save_total_limit=2,
        bf16=torch.cuda.is_bf16_supported(),
        # NOTE: bitsandbytes 8-bit optimizers are broken on Windows (0.44.1
        # ships with a ``str2optimizer8bit_blockwise`` NameError). The 0.5B
        # model is small enough that plain torch AdamW fits comfortably in
        # VRAM, and is also numerically cleaner. ``adamw_torch`` is the
        # cross-platform default; ``paged_adamw_8bit`` is only worth it for
        # multi-billion-parameter models where VRAM is the binding constraint.
        optim="adamw_torch",
        report_to="none",
    )

    # Dynamic padding collator: pads each batch to the longest sequence in
    # that batch (not to a global max_length), which saves substantial compute
    # when most examples are short and a few are long. ``label_pad_token_id``
    # keeps masked prompt positions at -100 so the loss still ignores them.
    data_collator = DataCollatorForSeq2Seq(
        tokenizer=tokenizer,
        model=model,
        label_pad_token_id=-100,
        pad_to_multiple_of=8,  # better tensor-core utilization
    )

    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=train_ds,
        eval_dataset=eval_ds,
        data_collator=data_collator,
    )

    print(
        f"Training: {len(train_ds)} examples, {args.epochs} epochs, "
        f"effective batch {args.batch_size * args.gradient_accumulation}"
    )
    trainer.train()

    # ---- Save adapters (NOT a full merge; merge is a separate, optional step) ----
    adapter_dir = CHECKPOINT_DIR / "lora_adapter"
    model.save_pretrained(str(adapter_dir))
    tokenizer.save_pretrained(str(adapter_dir))
    print(f"LoRA adapter saved to {adapter_dir}")
    print(
        "Next: deploy/hf_space/app.py loads this adapter on top of the base "
        "model for inference."
    )
    return 0


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="LoRA fine-tune Qwen2.5-0.5B on the LexiQuest instruction dataset."
    )
    parser.add_argument(
        "--model",
        default="Qwen/Qwen2.5-0.5B",
        help="Base model to fine-tune (default: Qwen2.5-0.5B).",
    )
    parser.add_argument("--epochs", type=int, default=3, help="Training epochs (default: 3).")
    parser.add_argument("--batch-size", type=int, default=1, help="Per-device batch (default: 1).")
    parser.add_argument(
        "--gradient-accumulation",
        type=int,
        default=8,
        help="Gradient accumulation steps (default: 8; effective batch = 8).",
    )
    parser.add_argument(
        "--learning-rate", type=float, default=2e-4, help="Peak LR (default: 2e-4)."
    )
    parser.add_argument(
        "--max-length", type=int, default=512, help="Max sequence length (default: 512)."
    )
    parser.add_argument("--lora-rank", type=int, default=16, help="LoRA rank (default: 16).")
    parser.add_argument("--lora-alpha", type=int, default=32, help="LoRA alpha (default: 32).")
    parser.add_argument(
        "--lora-dropout", type=float, default=0.05, help="LoRA dropout (default: 0.05)."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Run the full loop on a toy model with no Qwen download or GPU.",
    )
    parser.add_argument(
        "--dry-run-rows",
        type=int,
        default=8,
        help="Number of rows to train on in dry-run (default: 8).",
    )
    parser.add_argument(
        "--train",
        action="store_true",
        help=(
            "Run the REAL training (download Qwen2.5-0.5B, apply LoRA, train). "
            "Required explicitly so the script never accidentally downloads a "
            "~1GB model just because ``--dry-run`` was forgotten."
        ),
    )
    parser.add_argument(
        "--max-train-rows",
        type=int,
        default=0,
        help="Cap the training set to N rows (0 = all). Smoke-test convenience.",
    )
    args = parser.parse_args(argv)

    if args.dry_run:
        return _run_dry_train(args)
    if not args.train:
        parser.error(
            "No mode selected. Use --dry-run for a torch-free loop check, "
            "or --train for real fine-tuning."
        )
    return _run_real_train(args)


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
