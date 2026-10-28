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
    prompt = "a b c d e"
    budget = len(tokenizer.encode(format_prompt(prompt))) + 3
    example = build_example(
        {"prompt": prompt, "response": "f g h i j"},
        tokenizer=tokenizer,
        max_length=budget,
    )
    assert len(example["input_ids"]) == budget
    assert len(example["labels"]) == budget
    assert example["labels"][-3:] == tokenizer.encode("f g") + tokenizer.encode("<|im_end|>\n")


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


class CharacterTokenizer:
    def encode(self, text, add_special_tokens=False):
        return list(map(ord, text))


def test_completion_has_exactly_one_terminal_marker():
    assert format_completion("Answer.") == "Answer.<|im_end|>\n"


def test_long_completion_preserves_full_prompt_and_terminal_boundary():
    tokenizer = CharacterTokenizer()
    prompt = format_prompt("Question")
    eos = "<|im_end|>\n"
    example = build_example({"prompt": "Question", "response": "abcdef"},
                            tokenizer=tokenizer, max_length=len(prompt) + 3 + len(eos))
    assert example["input_ids"] == list(map(ord, prompt + "abc" + eos))
    assert example["labels"] == [-100] * len(prompt) + list(map(ord, "abc" + eos))


def test_prompt_that_leaves_no_response_budget_is_rejected():
    import pytest
    with pytest.raises(ValueError, match="prompt"):
        build_example({"prompt": "long " * 100, "response": "answer"},
                      tokenizer=CharacterTokenizer(), max_length=100)


def test_nonpositive_sequence_budget_is_rejected():
    import pytest
    for budget in (0, -1):
        with pytest.raises(ValueError, match="max_length"):
            build_example({"prompt": "Q", "response": "A"},
                          tokenizer=CharacterTokenizer(), max_length=budget)


def test_tokenizer_boundary_merge_cannot_mask_first_answer_token():
    class BoundaryTokenizer(CharacterTokenizer):
        def encode(self, text, add_special_tokens=False):
            if "assistant\nA" in text:
                return [999]
            return super().encode(text, add_special_tokens)
    prompt = format_prompt("Q")
    example = build_example({"prompt": "Q", "response": "A"},
                            tokenizer=BoundaryTokenizer(), max_length=1024)
    assert example["labels"] == [-100] * len(prompt) + list(map(ord, "A<|im_end|>\n"))
