"""Upload trained LexiQuest-LM LoRA adapter to HuggingFace Model Hub."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from huggingface_hub import HfApi, create_repo

ADAPTER_DIR = Path(__file__).resolve().parent.parent / "checkpoints" / "lora_adapter"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Upload LoRA adapter to Hugging Face Model Hub."
    )
    parser.add_argument(
        "--repo-id",
        required=True,
        help="Hugging Face repo ID (e.g. Phoomxo/lexiquest-lm-adapter).",
    )
    parser.add_argument(
        "--token",
        default=os.getenv("HF_TOKEN"),
        help="Hugging Face Access Token (requires write permission).",
    )
    parser.add_argument(
        "--private", action="store_true", help="Set repository to private."
    )

    args = parser.parse_args()

    if not args.token:
        print("ERROR: HuggingFace access token is required.", file=sys.stderr)
        print(
            "Please provide --token <YOUR_HF_TOKEN> or set HF_TOKEN environment variable.",
            file=sys.stderr,
        )
        print(
            "You can create a token at: https://huggingface.co/settings/tokens",
            file=sys.stderr,
        )
        return 1

    if not ADAPTER_DIR.exists():
        print(f"ERROR: Adapter directory not found at {ADAPTER_DIR}", file=sys.stderr)
        return 1

    api = HfApi(token=args.token)
    print(f"Creating / verifying repo '{args.repo_id}' on HuggingFace...")
    create_repo(
        repo_id=args.repo_id, token=args.token, exist_ok=True, private=args.private
    )

    print(
        f"Uploading files from {ADAPTER_DIR} to https://huggingface.co/{args.repo_id}..."
    )
    api.upload_folder(
        folder_path=str(ADAPTER_DIR),
        repo_id=args.repo_id,
        repo_type="model",
    )
    print(
        f"✅ Upload successful! Adapter is live at: https://huggingface.co/{args.repo_id}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
