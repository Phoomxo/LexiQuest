"""Tests for the evaluation harness (metric + report writer).

These cover the parts of ``evaluate.py`` that do not require torch: the
exact-match metric and the JSON report writer. The dry-run path of the
script itself is exercised by the smoke test in the dataset pipeline.
"""

from __future__ import annotations

import builtins
import json
import sys
from pathlib import Path
from types import ModuleType, SimpleNamespace

import pytest

import evaluate

from evaluate import StubModel, _exact_match_rate, _report




@pytest.fixture
def synthetic_evaluator(monkeypatch, tmp_path):
    """Exercise loading/report selection with CPU-only module stand-ins."""
    processed = tmp_path / "processed"
    reports = tmp_path / "reports"
    processed.mkdir()
    (processed / "test.jsonl").write_text(
        json.dumps({"prompt": "Synthetic prompt", "response": "Synthetic answer"}) + "\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(evaluate, "PROCESSED_DIR", processed)
    monkeypatch.setattr(evaluate, "REPORT_DIR", reports)
    imports = []
    loads = []
    evaluated = []
    hooks = SimpleNamespace(after_base_load=None, adapter_error=None)
    tokenizer = SimpleNamespace(pad_token=None, eos_token="<eos>")
    base = SimpleNamespace(identity="synthetic/base", eval=lambda: None)
    adapted = SimpleNamespace(identity="synthetic/adapter", eval=lambda: None)

    def load_tokenizer(name, **kwargs):
        loads.append(("tokenizer", name))
        return tokenizer

    def load_base(name, **kwargs):
        loads.append(("base", name))
        if hooks.after_base_load is not None:
            hooks.after_base_load()
        return base

    def load_adapter(model, path, **kwargs):
        assert model is base
        loads.append(("adapter", str(path)))
        if hooks.adapter_error is not None:
            raise hooks.adapter_error
        return adapted

    torch = ModuleType("torch")
    torch.float16 = "synthetic-float16"
    transformers = ModuleType("transformers")
    transformers.AutoTokenizer = SimpleNamespace(from_pretrained=load_tokenizer)
    transformers.AutoModelForCausalLM = SimpleNamespace(from_pretrained=load_base)
    peft = ModuleType("peft")
    peft.PeftModel = SimpleNamespace(from_pretrained=load_adapter)
    modules = {"torch": torch, "transformers": transformers, "peft": peft}
    for name, module in modules.items():
        monkeypatch.setitem(sys.modules, name, module)

    def compute(model, actual_tokenizer, rows, *, max_length):
        assert actual_tokenizer is tokenizer
        assert len(rows) == 1
        evaluated.append(model.identity)
        return 12.5

    monkeypatch.setattr(evaluate, "_compute_perplexity", compute)
    original_import = builtins.__import__

    def record_import(name, globals=None, locals=None, fromlist=(), level=0):
        if name.split(".")[0] in modules:
            imports.append(name)
        return original_import(name, globals, locals, fromlist, level)

    def run(arguments):
        # Observe attempted heavy imports, while preinstalled stub modules
        # ensure even the currently broken branch cannot load a real model.
        with monkeypatch.context() as scoped:
            scoped.setattr(builtins, "__import__", record_import)
            return evaluate.main([
                "--model", "synthetic/base", "--sample-count", "0",
                *arguments,
            ])

    return SimpleNamespace(
        run=run, imports=imports, loads=loads, evaluated=evaluated,
        reports=reports, base=base, adapted=adapted, hooks=hooks,
    )


@pytest.mark.parametrize("adapter_kind", ["missing", "file"])
def test_explicit_invalid_adapter_fails_before_import_or_load(
    tmp_path, synthetic_evaluator, adapter_kind
):
    adapter = tmp_path / "requested-adapter"
    if adapter_kind == "file":
        adapter.write_text("synthetic non-directory", encoding="utf-8")

    result = synthetic_evaluator.run(["--adapter", str(adapter)])

    assert result == 2
    assert synthetic_evaluator.imports == []
    assert synthetic_evaluator.loads == []
    assert synthetic_evaluator.evaluated == []
    assert not synthetic_evaluator.reports.exists()


@pytest.mark.parametrize("with_adapter", [False, True])
def test_real_evaluation_reports_the_artifact_actually_loaded(
    tmp_path, synthetic_evaluator, with_adapter
):
    arguments = []
    expected_checkpoint = "synthetic/base"
    expected_identity = "synthetic/base"
    expected_loads = [
        ("tokenizer", "synthetic/base"), ("base", "synthetic/base"),
    ]
    if with_adapter:
        adapter = tmp_path / "valid-adapter"
        adapter.mkdir()
        (adapter / "adapter_config.json").write_text("{}", encoding="utf-8")
        arguments = ["--adapter", str(adapter)]
        expected_checkpoint = str(adapter)
        expected_identity = "synthetic/adapter"
        expected_loads.append(("adapter", str(adapter)))

    assert synthetic_evaluator.run(arguments) == 0

    assert synthetic_evaluator.loads == expected_loads
    assert synthetic_evaluator.evaluated == [expected_identity]
    report = json.loads(
        (synthetic_evaluator.reports / "eval.json").read_text(encoding="utf-8")
    )
    assert report["checkpoint"] == expected_checkpoint
    assert report["n_test_rows"] == 1
    assert report["perplexity"] == 12.5


@pytest.mark.parametrize("failure", ["disappeared", "loader-error"])
def test_requested_adapter_failure_never_falls_back_or_writes_report(
    tmp_path, synthetic_evaluator, failure
):
    adapter = tmp_path / "requested-adapter"
    adapter.mkdir()
    expected_error = RuntimeError
    if failure == "disappeared":
        # Only this empty, test-owned temp directory is removed. It exists at
        # admission, then disappears during the simulated base-model load.
        synthetic_evaluator.hooks.after_base_load = adapter.rmdir
        synthetic_evaluator.hooks.adapter_error = FileNotFoundError(
            "synthetic adapter disappeared"
        )
        expected_error = FileNotFoundError
    else:
        synthetic_evaluator.hooks.adapter_error = RuntimeError(
            "synthetic adapter loading failed"
        )

    with pytest.raises(expected_error, match="synthetic adapter"):
        synthetic_evaluator.run(["--adapter", str(adapter)])

    assert synthetic_evaluator.loads == [
        ("tokenizer", "synthetic/base"),
        ("base", "synthetic/base"),
        ("adapter", str(adapter)),
    ]
    assert synthetic_evaluator.evaluated == []
    assert not synthetic_evaluator.reports.exists()
    assert adapter.is_dir() is (failure == "loader-error")


def test_dry_run_retains_stub_identity_without_heavy_imports(
    tmp_path, synthetic_evaluator
):
    assert synthetic_evaluator.run([
        "--dry-run", "--adapter", str(tmp_path / "unused-missing-adapter"),
    ]) == 0

    assert synthetic_evaluator.imports == []
    assert synthetic_evaluator.loads == []
    assert synthetic_evaluator.evaluated == []
    report = json.loads(
        (synthetic_evaluator.reports / "dry_run_eval.json").read_text(encoding="utf-8")
    )
    assert report["checkpoint"] == "dry-run-stub"
    assert report["perplexity"] is None
    assert not (synthetic_evaluator.reports / "eval.json").exists()


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
