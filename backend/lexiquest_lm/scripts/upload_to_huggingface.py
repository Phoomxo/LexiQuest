"""Upload the trained LexiQuest-LM LoRA adapter to a HuggingFace model repo.

Run after `lora_finetune.py --train` has produced
`backend/lexiquest_lm/checkpoints/lora_adapter/`.

Prerequisites
-------------
1. A free HuggingFace account (sign up at https://huggingface.co/join).
2. An access token with `write` scope:
   https://huggingface.co/settings/tokens -> New token -> Role: Write.
3. Install the upload tool:
       uv pip install --project backend/lexiquest_lm huggingface_hub
   (or: pip install huggingface_hub)
4. Log in once:
       huggingface-cli login
   Paste your write token when prompted. (Stored locally; never re-entered.)

Usage
-----
    # Uses HF_USERNAME env var, or auto-detects from the logged-in token.
    python backend/lexiquest_lm/scripts/upload_to_huggingface.py \
        --repo lexiquest-lm

    # Or pass the username explicitly:
    python backend/lexiquest_lm/scripts/upload_to_huggingface.py \
        --username your-username --repo lexiquest-lm

What it uploads
---------------
Everything under `checkpoints/lora_adapter/` (adapter weights + tokenizer +
config) plus a model card describing the model for the HF listing page.

After upload, the model is public (or private if --private) at:
    https://huggingface.co/<username>/lexiquest-lm
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Resolve the adapter directory relative to this script so it works from any
# CWD. scripts/upload_to_huggingface.py -> backend/lexiquest_lm/checkpoints.
_SCRIPT_DIR = Path(__file__).resolve().parent
_ADAPTER_DIR = _SCRIPT_DIR.parent / "checkpoints" / "lora_adapter"

_MODEL_CARD = """---
language:
  - en
  - th
tags:
  - vocabulary
  - education
  - english-learning
  - thai-learners
  - lora
  - qwen2.5
base_model: Qwen/Qwen2.5-0.5B
pipeline_tag: text-generation
license: mit
---

# LexiQuest-LM

A domain-specific vocabulary teaching small language model, fine-tuned for
the LexiQuest English-learning application. This is the research contribution
of the LexiQuest thesis: instead of depending on a third-party LLM API,
LexiQuest ships its own compact model trained on a curated
vocabulary-teaching dataset.

## Model details

- **Base model**: Qwen2.5-0.5B
- **Fine-tuning**: LoRA (rank 16, alpha 32, dropout 0.05)
- **Trainable parameters**: 8.8M / 502.8M (1.75%)
- **Training time**: ~50 minutes on a single NVIDIA RTX 3050 (8GB)
- **Adapter size**: ~35MB

## Training data

8,588 instruction-tuning examples stratified across three teaching tasks:
example sentences, micro-stories, and word explanations. Sourced from the
app's CEFR word bank (19 seed words) expanded with Oxford 3000 + CEFR-J
wordlists (1,862 words total), enriched via dictionaryapi.dev + Datamuse,
and formatted with POS-aware, CEFR-stratified templates.

| Split | Total | Sentence | Story | Explanation |
|---|---|---|---|---|
| train | 6,872 | 3,357 | 2,025 | 1,490 |
| validation | 858 | 419 | 253 | 186 |
| test | 858 | 419 | 253 | 186 |

## Evaluation

- **Test perplexity**: 3.32
- **Final train loss**: 1.20 (from 4.36, -72%)
- **Final eval loss**: 1.21

## Intended use

Generates short English teaching content (one example sentence, a 2-4
sentence micro-story, or a brief word explanation) given a target word and
CEFR level. Designed for Thai learners of English. Output is consumed by
the LexiQuest Flutter app's AI tutor and fill-in-the-blanks exercises.

## Limitations

- Template-heavy training data means outputs can repeat the same structure;
  quality improves when augmented with real (Tatoeba / Gemini-synthetic)
  sentences, which is planned future work.
- The 0.5B base is intentionally small for cost-free deployment; it cannot
  match the fluency of multi-billion-parameter models.
- Outputs should be treated as teaching scaffolding, not authoritative
  definitions.
"""


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Upload the LexiQuest-LM adapter to a HuggingFace model repo."
    )
    parser.add_argument(
        "--username",
        default=None,
        help="HF username. If omitted, auto-detected from the logged-in token.",
    )
    parser.add_argument(
        "--repo",
        default="lexiquest-lm",
        help="Repo name (default: lexiquest-lm).",
    )
    parser.add_argument(
        "--adapter-dir",
        type=Path,
        default=_ADAPTER_DIR,
        help="Adapter directory (default: backend/lexiquest_lm/checkpoints/lora_adapter).",
    )
    parser.add_argument(
        "--private",
        action="store_true",
        help="Make the repo private (default: public).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the planned upload without touching the network.",
    )
    args = parser.parse_args(argv)

    if not args.adapter_dir.exists():
        print(
            f"ERROR: adapter not found at {args.adapter_dir}. "
            "Run lora_finetune.py --train first.",
            file=sys.stderr,
        )
        return 2

    try:
        from huggingface_hub import HfApi, whoami
    except ImportError:
        print(
            "ERROR: huggingface_hub not installed. Run:\n"
            "  uv pip install --project backend/lexiquest_lm huggingface_hub\n"
            "or: pip install huggingface_hub",
            file=sys.stderr,
        )
        return 2

    username = args.username
    if username is None:
        try:
            username = whoami()["name"]
        except Exception as error:  # noqa: BLE001
            print(
                f"ERROR: could not detect username from login ({error}). "
                "Run `huggingface-cli login` or pass --username.",
                file=sys.stderr,
            )
            return 2

    repo_id = f"{username}/{args.repo}"
    print(f"Target repo: {repo_id}")
    print(f"Adapter dir: {args.adapter_dir}")
    print(f"Files to upload:")
    for path in sorted(args.adapter_dir.iterdir()):
        print(f"  {path.name} ({path.stat().st_size:,} bytes)")

    if args.dry_run:
        print("\n[dry-run] No files uploaded. Re-run without --dry-run to upload.")
        return 0

    api = HfApi()
    api.create_repo(repo_id=repo_id, private=args.private, exist_ok=True)

    # Write the model card into the adapter dir so it uploads alongside the
    # weights. Truncates first so re-runs replace it cleanly.
    card_path = args.adapter_dir / "README.md"
    card_path.write_text(_MODEL_CARD, encoding="utf-8")

    api.upload_folder(
        folder_path=str(args.adapter_dir),
        repo_id=repo_id,
        repo_type="model",
        allow_patterns=["*.json", "*.safetensors", "*.bin", "*.md", "*.txt"],
        ignore_patterns=[".env*", "*.pem", "*.key", "*secret*", "*.log"],
        commit_message="Upload LexiQuest-LM LoRA adapter",
    )
    print(f"\nUploaded. View at: https://huggingface.co/{repo_id}")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
