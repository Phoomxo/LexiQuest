"""Synthetic offline regressions; no model, real data, GPU or upload."""
import argparse
import importlib.util
import sys
import types
from pathlib import Path

import pytest
import lora_finetune as train
import tokenise_dataset


@pytest.mark.parametrize("suffix", [[33, 44], [55, 66, 77]])
def test_dry_loop_uses_only_unmasked_positions(monkeypatch, tmp_path, suffix):
    import lexiquest_lm.dataset.io as io
    monkeypatch.setattr(io, "read_jsonl", lambda _: iter([{}]))
    monkeypatch.setattr(train, "CHECKPOINT_DIR", tmp_path)
    monkeypatch.setattr(tokenise_dataset, "build_example", lambda *a, **kw:
                        {"input_ids": [11, 22] + suffix, "labels": [-100, -100] + suffix})
    seen = []
    def trace(frame, event, value):
        if event == "return" and frame.f_code.co_name in ("_featurise", "_completion_features"):
            seen.append(value)
        return trace
    old = sys.gettrace()
    try:
        sys.settrace(trace)
        assert train._run_dry_train(argparse.Namespace(dry_run_rows=1, max_length=64,
                                      epochs=1, learning_rate=0.01)) == 0
    finally:
        sys.settrace(old)
    assert seen == [suffix]
    assert (tmp_path / "DRY_RUN_OK").exists()


def test_zero_epoch_dry_run_rejected_without_success_marker(monkeypatch, tmp_path):
    monkeypatch.setattr(train, "CHECKPOINT_DIR", tmp_path)
    import lexiquest_lm.dataset.io as io
    monkeypatch.setattr(io, "read_jsonl", lambda _: iter([{}]))
    monkeypatch.setattr(tokenise_dataset, "build_example", lambda *a, **kw:
                        {"input_ids": [11, 33], "labels": [-100, 33]})
    with pytest.raises(ValueError, match="epochs"):
        train._run_dry_train(argparse.Namespace(epochs=0, dry_run_rows=1,
                                               max_length=64, learning_rate=0.01))
    assert not (tmp_path / "DRY_RUN_OK").exists()


def test_upload_dry_run_without_username_never_calls_network(monkeypatch, tmp_path, capsys):
    path = Path(__file__).resolve().parents[1] / "scripts/upload_to_huggingface.py"
    spec = importlib.util.spec_from_file_location("offline_upload", path)
    upload = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(upload)
    calls = []
    def forbidden(*args, **kwargs):
        calls.append("network")
        raise AssertionError("network forbidden")
    monkeypatch.setitem(sys.modules, "huggingface_hub",
                        types.SimpleNamespace(HfApi=forbidden, whoami=forbidden))
    (tmp_path / "adapter.json").write_text("{}", encoding="utf-8")
    result = upload.main(["--dry-run", "--adapter-dir", str(tmp_path)])
    assert calls == []
    assert result == 2
    assert "--username" in capsys.readouterr().err
    assert list(tmp_path.iterdir()) == [tmp_path / "adapter.json"]


def test_all_masked_example_cannot_produce_success_marker(monkeypatch, tmp_path):
    import lexiquest_lm.dataset.io as io
    monkeypatch.setattr(io, "read_jsonl", lambda _: iter([{}]))
    monkeypatch.setattr(train, "CHECKPOINT_DIR", tmp_path)
    monkeypatch.setattr(tokenise_dataset, "build_example", lambda *a, **kw:
                        {"input_ids": [11, 22], "labels": [-100, -100]})
    with pytest.raises(ValueError, match="unmasked"):
        train._run_dry_train(argparse.Namespace(epochs=1, dry_run_rows=1,
                                               max_length=64, learning_rate=0.01))
    assert not (tmp_path / "DRY_RUN_OK").exists()


def test_explicit_username_upload_plan_needs_no_hub_dependency(monkeypatch, tmp_path, capsys):
    path = Path(__file__).resolve().parents[1] / "scripts/upload_to_huggingface.py"
    spec = importlib.util.spec_from_file_location("offline_upload_explicit", path)
    upload = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(upload)
    monkeypatch.setitem(sys.modules, "huggingface_hub", None)
    (tmp_path / "adapter.json").write_text("{}", encoding="utf-8")
    assert upload.main(["--dry-run", "--username", "offline-user",
                        "--adapter-dir", str(tmp_path)]) == 0
    assert "offline-user/lexiquest-lm" in capsys.readouterr().out
    assert list(tmp_path.iterdir()) == [tmp_path / "adapter.json"]
