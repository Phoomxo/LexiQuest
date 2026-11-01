"""Runtime compatibility guard for the OmniVoice CUDA stack.

This module deliberately never imports Torch, Torchaudio, or OmniVoice, so a
misconfigured runtime is reported before GPU work starts.
"""

from __future__ import annotations

import importlib.metadata
import re
from collections.abc import Callable
from dataclasses import dataclass

TORCH_VERSION = "2.11.0+cu128"
TORCHAUDIO_VERSION = "2.11.0+cu128"
OMNIVOICE_VERSION = "0.2.1"

TORCH_PACKAGE = "torch"
TORCHAUDIO_PACKAGE = "torchaudio"
OMNIVOICE_PACKAGE = "omnivoice"

_EXPECTED_VERSIONS: tuple[tuple[str, str], ...] = (
    (TORCH_PACKAGE, TORCH_VERSION),
    (TORCHAUDIO_PACKAGE, TORCHAUDIO_VERSION),
    (OMNIVOICE_PACKAGE, OMNIVOICE_VERSION),
)


@dataclass(frozen=True, slots=True)
class RuntimeCompatibility:
    """Immutable outcome of a runtime compatibility check."""

    is_compatible: bool
    reason: str


class RuntimeCompatibilityError(RuntimeError):
    """Raised when the active runtime does not match the supported pin."""


def evaluate_runtime_compatibility(
    *,
    torch: str | None,
    torchaudio: str | None,
    omnivoice: str | None,
) -> RuntimeCompatibility:
    """Compare detected versions against the supported runtime."""

    detected = {
        TORCH_PACKAGE: torch,
        TORCHAUDIO_PACKAGE: torchaudio,
        OMNIVOICE_PACKAGE: omnivoice,
    }
    mismatches: list[str] = []
    for package, expected in _EXPECTED_VERSIONS:
        detected_version = detected[package]
        if detected_version != expected:
            rendered = "not installed" if detected_version is None else detected_version
            mismatches.append(f"{package}: expected {expected}, detected {rendered}")
    if mismatches:
        return RuntimeCompatibility(
            is_compatible=False,
            reason="; ".join(mismatches),
        )
    return RuntimeCompatibility(is_compatible=True, reason="")


def _installed_version(package: str) -> str | None:
    """Read an installed distribution version without importing it."""

    try:
        return importlib.metadata.version(package)
    except importlib.metadata.PackageNotFoundError:
        return None


def require_supported_runtime(
    *,
    version_of: Callable[[str], str | None] = _installed_version,
) -> None:
    """Fail fast when the active runtime is unsupported."""

    result = evaluate_runtime_compatibility(
        torch=version_of(TORCH_PACKAGE),
        torchaudio=version_of(TORCHAUDIO_PACKAGE),
        omnivoice=version_of(OMNIVOICE_PACKAGE),
    )
    if not result.is_compatible:
        raise RuntimeCompatibilityError(result.reason)


def require_secure_supported_runtime(
    *,
    version_of: Callable[[str], str | None] = _installed_version,
) -> None:
    """Reject unsafe metadata before requiring the exact supported GPU pair.

    No currently supported pair meets both gates. A patched version alone does
    not approve a new Torch/Torchaudio/CUDA combination.
    """
    detected = {
        package: version_of(package)
        for package in (
            TORCH_PACKAGE,
            TORCHAUDIO_PACKAGE,
            OMNIVOICE_PACKAGE,
            "setuptools",
        )
    }
    # GHSA-rrmf-rvhw-rf47; GHSA-h35f-9h28-mq5c; GHSA-xmj3-9gf7-h52w.
    # Torch 2.11 requires setuptools<82; neither pin can be upgraded alone.
    for package, floor in (
        (TORCH_PACKAGE, (2, 13, 0)),
        ("setuptools", (84, 1, 0)),
    ):
        value = detected[package]
        match = re.fullmatch(
            r"([0-9]+)\.([0-9]+)\.([0-9]+)(?:\+[A-Za-z0-9._-]+)?",
            value or "",
        )
        if match is None or tuple(map(int, match.groups())) < floor:
            raise RuntimeCompatibilityError(
                f"GPU Voice release blocked by security policy: {package} must "
                f"meet {'.'.join(map(str, floor))}; detected {value!r}. "
                "No patched supported GPU runtime is currently approved."
            )
    require_supported_runtime(version_of=lambda package: detected[package])


__all__ = [
    "OMNIVOICE_VERSION",
    "RuntimeCompatibility",
    "RuntimeCompatibilityError",
    "TORCHAUDIO_VERSION",
    "TORCH_VERSION",
    "evaluate_runtime_compatibility",
    "require_secure_supported_runtime",
    "require_supported_runtime",
]
