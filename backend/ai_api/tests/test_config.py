"""Fail-closed production configuration contracts."""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from lexiquest_ai.config import Settings


AUTHORITY = "gcp-kms-hmac-sha256-v1"
KMS_KEY_VERSION = (
    "projects/test/locations/global/keyRings/delete/cryptoKeys/receipt/"
    "cryptoKeyVersions/1"
)
OLD_KMS_KEY_VERSION = f"{KMS_KEY_VERSION[:-1]}2"


def _deletion_config() -> dict[str, object]:
    return {
        "account_deletion_server_export_authority": AUTHORITY,
        "account_deletion_export_bucket": "private-delete-exports",
        "account_deletion_export_kms_key_version": KMS_KEY_VERSION,
        "account_deletion_export_retention_seconds": 7 * 24 * 3600,
        "account_deletion_recovery_retention_seconds": 7 * 24 * 3600,
        "account_deletion_export_maximum_documents": 10_000,
        "account_deletion_export_maximum_bytes": 50 * 1024 * 1024,
    }


def test_account_deletion_production_authority_is_default_off() -> None:
    settings = Settings()

    assert settings.account_deletion_enabled is False
    assert settings.account_deletion_server_export_authority == ""
    assert settings.account_deletion_export_bucket == ""
    assert settings.account_deletion_export_kms_key_version == ""
    assert settings.account_deletion_export_trusted_kms_key_versions == ""
    assert settings.account_deletion_export_retention_seconds == 0


def test_complete_gcp_deletion_export_configuration_is_accepted() -> None:
    settings = Settings(
        **_deletion_config(),
        account_deletion_export_trusted_kms_key_versions=(
            f" {OLD_KMS_KEY_VERSION}, {OLD_KMS_KEY_VERSION} "
        ),
    )

    assert settings.account_deletion_server_export_authority == AUTHORITY
    assert settings.account_deletion_export_bucket == "private-delete-exports"
    assert (
        settings.account_deletion_export_trusted_kms_key_versions
        == OLD_KMS_KEY_VERSION
    )


@pytest.mark.parametrize(
    "override",
    [
        {"account_deletion_server_export_authority": "unknown"},
        {
            "account_deletion_server_export_authority": AUTHORITY,
            "account_deletion_export_bucket": "private-delete-exports",
        },
        {"account_deletion_export_bucket": "orphaned-partial-config"},
        {
            **_deletion_config(),
            "account_deletion_export_bucket": "Invalid Bucket Name",
        },
        {
            **_deletion_config(),
            "account_deletion_export_kms_key_version": "not-a-kms-version",
        },
        {
            **_deletion_config(),
            "account_deletion_export_trusted_kms_key_versions": (
                f"{OLD_KMS_KEY_VERSION},not-a-kms-version"
            ),
        },
        {
            **_deletion_config(),
            "account_deletion_export_retention_seconds": 24 * 3600,
            "account_deletion_recovery_retention_seconds": 7 * 24 * 3600,
        },
    ],
)
def test_unknown_partial_or_too_short_export_configuration_fails_closed(
    override: dict[str, object],
) -> None:
    with pytest.raises(ValidationError):
        Settings(**override)
