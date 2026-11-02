"""Fail-closed production configuration contracts."""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from lexiquest_ai.config import Settings
import json


AUTHORITY = "gcp-kms-hmac-sha256-v1"
KMS_KEY_VERSION = (
    "projects/test/locations/global/keyRings/delete/cryptoKeys/receipt/"
    "cryptoKeyVersions/1"
)
OLD_KMS_KEY_VERSION = f"{KMS_KEY_VERSION[:-1]}2"


def billing_config():
    return {'billing_enabled': True, 'billing_policy_revision': 'synthetic-v1',
        'billing_account_binding_key': 'synthetic-only-account-key-00000000',
        'billing_products_json': json.dumps([{'productId': 'synthetic-premium', 'basePlanId': 'synthetic-monthly',
            'entitlements': ['managedContent'], 'dailyManagedUnits': 2}])}


def test_billing_is_disabled_and_free_content_preserved_by_default():
    settings = Settings()
    assert not settings.billing_enabled
    assert not settings.billing_managed_content_required


@pytest.mark.parametrize('override', [
    {'billing_products_json': '[]'}, {'billing_products_json': '{}'},
    {'billing_products_json': 'invalid'}, {'billing_policy_revision': ''},
    {'billing_account_binding_key': 'short-synthetic-secret'},
])
def test_enabled_billing_rejects_missing_policy_or_binding_key_without_echoing_inputs(override):
    with pytest.raises(ValidationError) as caught:
        Settings(**{**billing_config(), **override})
    assert 'short-synthetic-secret' not in str(caught.value)
    assert 'synthetic-only-account-key-00000000' not in str(caught.value)


def test_billing_policy_uses_explicit_product_limits_and_secret_repr():
    settings = Settings(**billing_config())
    assert settings.billing_policy().products[0].daily_managed_units == 2
    assert 'synthetic-only-account-key-00000000' not in repr(settings)
    with pytest.raises(ValidationError):
        Settings(billing_managed_content_required=True)


@pytest.mark.parametrize('entitlements, units', [
    (['managedContent'], 0), (['offlinePremium'], 10),
    (['managedContent', 'aiTutorUnlimited'], 10),
])
def test_managed_content_gate_rejects_zero_quota_or_unimplemented_product_claims(entitlements, units):
    configuration = billing_config()
    products = json.loads(configuration['billing_products_json'])
    products[0].update(entitlements=entitlements, dailyManagedUnits=units)
    configuration['billing_products_json'] = json.dumps(products)
    with pytest.raises(ValidationError, match='positive managed-only'):
        Settings(**configuration, billing_managed_content_required=True)


def test_billing_verification_budget_is_trusted_bounded_configuration(monkeypatch):
    assert Settings(**billing_config()).billing_policy().verification_requests_per_minute == 20
    monkeypatch.setenv('LEXIQUEST_AI_BILLING_VERIFICATION_REQUESTS_PER_MINUTE', '7')
    assert Settings(**billing_config()).billing_policy().verification_requests_per_minute == 7
    for limit in [0, 121, -1]:
        with pytest.raises(ValidationError):
            Settings(**billing_config(), billing_verification_requests_per_minute=limit)


def test_production_billing_requires_both_pubsub_audience_and_service_identity():
    with pytest.raises(ValidationError, match='Pub/Sub'):
        Settings(**{**billing_config(), 'environment': 'production'})
    with pytest.raises(ValidationError, match='configured together'):
        Settings(**{**billing_config(), 'billing_rtdn_audience': 'https://synthetic.example.test/notifications'})
    settings = Settings(**{**billing_config(), 'environment': 'production',
        'billing_rtdn_audience': 'https://synthetic.example.test/notifications',
        'billing_rtdn_service_account_email': 'synthetic@synthetic-project.iam.gserviceaccount.com'})
    assert settings.billing_enabled


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
