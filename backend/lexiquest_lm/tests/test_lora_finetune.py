"""CPU-only regression checks for the dry-run training loop."""

import argparse
import json

import lora_finetune
import tokenise_dataset


def test_dry_run_training_uses_the_unmasked_response(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(lora_finetune, "PROCESSED_DIR", tmp_path)
    monkeypatch.setattr(lora_finetune, "CHECKPOINT_DIR", tmp_path / "checkpoint")
    monkeypatch.setattr(
        tokenise_dataset,
        "build_example",
        lambda row, **kwargs: {
            "input_ids": [11, 12, row["response"]],
            "labels": [-100, -100, row["response"]],
        },
    )
    args = argparse.Namespace(
        dry_run_rows=1, max_length=32, epochs=1, learning_rate=0.01
    )

    def train(response):
        (tmp_path / "train.jsonl").write_text(
            json.dumps({"response": response}) + "\n", encoding="utf-8"
        )
        assert lora_finetune._run_dry_train(args) == 0
        return capsys.readouterr().out

    assert train(99) != train(42)
