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
    require_secure_supported_runtime,
    require_supported_runtime,
)


def test_supported_version_pins_are_exact() -> None:
    assert TORCH_VERSION == "2.11.0+cu128"
    assert TORCHAUDIO_VERSION == "2.11.0+cu128"
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
    (TORCH_VERSION, "2.11.0+cpu", OMNIVOICE_VERSION, "2.11.0+cpu"),
    ("2.11.0+cu121", TORCHAUDIO_VERSION, OMNIVOICE_VERSION, "2.11.0+cu121"),
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


def test_security_guard_rejects_the_exact_supported_but_vulnerable_pair() -> None:
    with pytest.raises(RuntimeCompatibilityError, match="security.*torch"):
        require_secure_supported_runtime(version_of=_version_lookup({
            "torch": TORCH_VERSION,
            "torchaudio": TORCHAUDIO_VERSION,
            "omnivoice": OMNIVOICE_VERSION,
            "setuptools": "81.0.0",
        }))


@pytest.mark.parametrize("value", [None, "unknown", "2.13.0rc1", "2.12.1"])
def test_security_guard_denies_missing_malformed_prerelease_or_old_torch(
    value: str | None,
) -> None:
    with pytest.raises(RuntimeCompatibilityError, match="security.*torch"):
        require_secure_supported_runtime(version_of=_version_lookup({
            "torch": value,
            "torchaudio": TORCHAUDIO_VERSION,
            "omnivoice": OMNIVOICE_VERSION,
            "setuptools": "84.1.0",
        }))


@pytest.mark.parametrize("value", [None, "unknown", "84.1.0rc1", "83.0.0"])
def test_security_guard_denies_unpatched_or_unverifiable_setuptools(
    value: str | None,
) -> None:
    with pytest.raises(RuntimeCompatibilityError, match="security.*setuptools"):
        require_secure_supported_runtime(version_of=_version_lookup({
            "torch": "2.13.0+cu132",
            "torchaudio": TORCHAUDIO_VERSION,
            "omnivoice": OMNIVOICE_VERSION,
            "setuptools": value,
        }))


def test_security_floor_does_not_approve_a_future_or_mismatched_gpu_pair() -> None:
    calls: list[str] = []
    versions = {
        "torch": "2.13.0+cu132",
        "torchaudio": TORCHAUDIO_VERSION,
        "omnivoice": OMNIVOICE_VERSION,
        "setuptools": "84.1.0",
    }

    def changing_lookup(package: str) -> str | None:
        calls.append(package)
        if calls.count(package) > 1:
            return TORCH_VERSION if package == "torch" else versions[package]
        return versions[package]

    with pytest.raises(RuntimeCompatibilityError, match="expected 2.11.0"):
        require_secure_supported_runtime(version_of=changing_lookup)
    assert sorted(calls) == sorted(versions)
