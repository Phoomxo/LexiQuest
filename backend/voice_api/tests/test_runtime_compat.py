"""Tests for the OmniVoice runtime compatibility guard.

These tests pin the exact supported Torch / Torchaudio / OmniVoice runtime and
the behaviour of the pure evaluator and fail-fast requirement. They import only
``lexiquest_voice.runtime_compat`` and never import torch, torchaudio, or
omnivoice, so the CPU suite can collect them without a GPU environment.
"""

from __future__ import annotations

from collections.abc import Callable

import pytest

from lexiquest_voice.runtime_compat import (
    OMNIVOICE_VERSION,
    TORCH_VERSION,
    TORCHAUDIO_VERSION,
    RuntimeCompatibilityError,
    evaluate_runtime_compatibility,
    require_supported_runtime,
)


def test_supported_version_pins_are_exact() -> None:
    assert TORCH_VERSION == "2.8.0+cu128"
    assert TORCHAUDIO_VERSION == "2.8.0+cu128"
    assert OMNIVOICE_VERSION == "0.2.1"


def test_evaluator_accepts_the_supported_runtime() -> None:
    result = evaluate_runtime_compatibility(
        torch=TORCH_VERSION,
        torchaudio=TORCHAUDIO_VERSION,
        omnivoice=OMNIVOICE_VERSION,
    )

    assert result.is_compatible is True
    assert result.reason == ""


_REJECTION_CASES: list[
    tuple[str | None, str | None, str | None, str | tuple[str, ...]]
] = [
    (None, TORCHAUDIO_VERSION, OMNIVOICE_VERSION, "torch"),
    (TORCH_VERSION, None, OMNIVOICE_VERSION, "torchaudio"),
    (TORCH_VERSION, TORCHAUDIO_VERSION, None, "omnivoice"),
    (
        "2.13.0+cu132",
        "2.11.0+cpu",
        OMNIVOICE_VERSION,
        ("2.13.0+cu132", "2.11.0+cpu"),
    ),
    (TORCH_VERSION, "2.8.0+cpu", OMNIVOICE_VERSION, "2.8.0+cpu"),
    ("2.8.0+cu121", TORCHAUDIO_VERSION, OMNIVOICE_VERSION, "2.8.0+cu121"),
    (TORCH_VERSION, TORCHAUDIO_VERSION, "0.3.0", "0.3.0"),
]

_REJECTION_IDS = [
    "torch_missing",
    "torchaudio_missing",
    "omnivoice_missing",
    "broken_current_pair",
    "torchaudio_cpu_wheel",
    "torch_wrong_cuda_suffix",
    "omnivoice_wrong_release",
]


@pytest.mark.parametrize(
    ("torch", "torchaudio", "omnivoice", "reason_substring"),
    _REJECTION_CASES,
    ids=_REJECTION_IDS,
)
def test_evaluator_rejects_unsupported_runtimes(
    torch: str | None,
    torchaudio: str | None,
    omnivoice: str | None,
    reason_substring: str | tuple[str, ...],
) -> None:
    result = evaluate_runtime_compatibility(
        torch=torch,
        torchaudio=torchaudio,
        omnivoice=omnivoice,
    )

    assert result.is_compatible is False
    assert result.reason
    expected = (
        reason_substring if isinstance(reason_substring, tuple) else (reason_substring,)
    )
    assert any(token in result.reason for token in expected)


def _version_lookup(
    versions: dict[str, str | None],
) -> Callable[[str], str | None]:
    table = dict(versions)

    def lookup(name: str) -> str | None:
        return table.get(name)

    return lookup


def test_require_supported_runtime_accepts_the_supported_set() -> None:
    version_of = _version_lookup(
        {
            "torch": TORCH_VERSION,
            "torchaudio": TORCHAUDIO_VERSION,
            "omnivoice": OMNIVOICE_VERSION,
        }
    )

    require_supported_runtime(version_of=version_of)


@pytest.mark.parametrize(
    "versions",
    [
        {
            "torch": None,
            "torchaudio": TORCHAUDIO_VERSION,
            "omnivoice": OMNIVOICE_VERSION,
        },
        {
            "torch": "2.13.0+cu132",
            "torchaudio": "2.11.0+cpu",
            "omnivoice": OMNIVOICE_VERSION,
        },
        {
            "torch": TORCH_VERSION,
            "torchaudio": TORCHAUDIO_VERSION,
            "omnivoice": "0.3.0",
        },
    ],
    ids=["missing_package", "broken_current_pair", "wrong_omnivoice_release"],
)
def test_require_supported_runtime_rejects_mismatches(
    versions: dict[str, str | None],
) -> None:
    with pytest.raises(RuntimeCompatibilityError):
        require_supported_runtime(version_of=_version_lookup(versions))
