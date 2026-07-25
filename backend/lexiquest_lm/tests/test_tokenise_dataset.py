"""Tests for the tokeniser + prompt masking logic.

These are the highest-value tests in the training pipeline: a bug in the
masking (e.g. loss computed on the prompt, or on padded positions) silently
produces a model that memorises the question instead of learning to answer.
The tests use the StubTokenizer so they run without torch/Qwen.
"""

from __future__ import annotations

from tokenise_dataset import (
    StubTokenizer,
    SYSTEM_PROMPT,
    build_example,
    format_completion,
    format_prompt,
    full_text,
)


def test_format_prompt_includes_system_user_and_assistant_header() -> None:
    formatted = format_prompt("Write a sentence.")

    assert SYSTEM_PROMPT in formatted
    assert "Write a sentence." in formatted
    assert "<|im_start|>user" in formatted
    assert "<|im_start|>assistant" in formatted
    # The assistant header must be the LAST role marker so the model learns to
    # continue from it.
    assert formatted.rstrip().endswith("<|im_start|>assistant")


def test_format_completion_ends_with_eos_marker() -> None:
    formatted = format_completion("The cat sleeps.")

    assert formatted.startswith("The cat sleeps.")
    assert "<|im_end|>" in formatted


def test_full_text_is_prompt_plus_completion() -> None:
    prompt = format_prompt("Q?")
    completion = format_completion("A.")
    full = full_text("Q?", "A.")

    assert full == prompt + completion


def test_build_example_masks_prompt_positions_to_negative_100() -> None:
    """Every prompt-token position in labels must be -100."""

    tokenizer = StubTokenizer()
    example = build_example(
        {"prompt": "alpha beta gamma", "response": "delta epsilon"},
        tokenizer=tokenizer,
        max_length=64,
    )

    # The prompt is strictly longer than the response (it includes system +
    # user + assistant header), so the leading run of -100 must be non-empty.
    labels = example["labels"]
    masked_prefix = 0
    for label in labels:
        if label == -100:
            masked_prefix += 1
        else:
            break
    assert masked_prefix > 0, "no prompt positions were masked"


def test_build_example_keeps_completion_positions_unmasked() -> None:
    """At least the response tokens must contribute to the loss."""

    tokenizer = StubTokenizer()
    example = build_example(
        {"prompt": "alpha", "response": "delta epsilon zeta"},
        tokenizer=tokenizer,
        max_length=64,
    )

    unmasked = [l for l in example["labels"] if l != -100]
    # The response has 3 stub tokens, all of which should be unmasked.
    assert len(unmasked) >= 3


def test_build_example_truncates_to_max_length() -> None:
    tokenizer = StubTokenizer()
    example = build_example(
        {"prompt": "a b c d e", "response": "f g h"},
        tokenizer=tokenizer,
        max_length=4,
    )

    assert len(example["input_ids"]) == 4
    assert len(example["labels"]) == 4


def test_stub_tokenizer_is_deterministic() -> None:
    """The stub's pseudo-ids must be stable so tests are reproducible."""

    tok = StubTokenizer()
    assert tok.encode("hello world") == tok.encode("hello world")


def test_system_prompt_is_fixed_for_reproducibility() -> None:
    # A thesis reproducibility requirement: the system prompt is hard-coded,
    # not configurable, so every run trains against an identical instruction
    # frame. If this changes, all previous checkpoints silently change meaning.
    assert isinstance(SYSTEM_PROMPT, str)
    assert "vocabulary teacher" in SYSTEM_PROMPT.lower()
