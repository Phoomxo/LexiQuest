from datetime import UTC, datetime, timedelta
import hashlib

import pytest

from lexiquest_ai.billing import (
    BillingError, BillingPolicy, BillingProduct, BillingService, PurchaseRefresh, VerifiedPlayPurchase,
)
from lexiquest_ai.firestore_billing import FirestoreBillingStore
from test_firestore_billing import Documents


NOW = datetime(2026, 11, 1, 3, tzinfo=UTC)
POLICY = BillingPolicy('com.lexiquest.app', 'synthetic-policy-v1', (
    BillingProduct('synthetic-premium', 'synthetic-monthly', frozenset({'managedContent'}), 2),
))


class Play:
    def __init__(self):
        self.result = None
        self.acknowledgements = []
        self.verifications = []

    def verify(self, **kwargs):
        self.verifications.append(kwargs)
        return self.result

    def acknowledge(self, **kwargs):
        self.acknowledgements.append(kwargs)


class Store:
    def __init__(self):
        self.writes = []

    def begin_refresh(self, *, firebase_uid, token_fingerprint, now_utc):
        return PurchaseRefresh(token_fingerprint, firebase_uid, 'synthetic-lease', now_utc + timedelta(seconds=30))

    def consume_verification_budget(self, *, firebase_uid, policy, now_utc):
        pass

    def abort_refresh(self, refresh):
        pass


def test_purchase_for_a_cannot_activate_b_or_write_an_entitlement():
    play, store = Play(), Store()
    service = BillingService(policy=POLICY, play=play, store=store,
                             account_binding_key=b'synthetic-only-account-key-00000000', now_utc=lambda: NOW)
    play.result = VerifiedPlayPurchase('synthetic-premium', 'synthetic-monthly',
        service.account_identifier('synthetic-a'), 'SUBSCRIPTION_STATE_ACTIVE',
        NOW + timedelta(days=2), NOW, True)

    with pytest.raises(BillingError, match='owner_mismatch'):
        service.verify_purchase(firebase_uid='synthetic-b', purchase_token='synthetic-token-secret')

    assert store.writes == []
    assert play.acknowledgements == []


def service_fixture(*, acknowledged=True, state='SUBSCRIPTION_STATE_ACTIVE'):
    play, documents = Play(), Documents()
    clock = [NOW]
    service = BillingService(policy=POLICY, play=play, store=FirestoreBillingStore(documents),
        account_binding_key=b'synthetic-only-account-key-00000000', now_utc=lambda: clock[0])
    play.result = VerifiedPlayPurchase('synthetic-premium', 'synthetic-monthly',
        service.account_identifier('synthetic-a'), state, NOW + timedelta(days=2), NOW, acknowledged)
    return service, play, documents, clock


def test_verified_purchase_and_restore_keep_one_owner_bound_purchase_without_raw_token():
    service, play, documents, _ = service_fixture()
    for _ in range(2):
        snapshot = service.verify_purchase(firebase_uid='synthetic-a', purchase_token='synthetic-token-secret')
        assert snapshot.grant('managedContent').daily_managed_units == 2
    assert len([path for path in documents.values if path.startswith('billing_purchases/')]) == 1
    assert 'synthetic-token-secret' not in repr(documents.values)
    assert play.acknowledgements == []


@pytest.mark.parametrize('state', ['SUBSCRIPTION_STATE_PENDING', 'SUBSCRIPTION_STATE_ON_HOLD',
    'SUBSCRIPTION_STATE_PAUSED', 'SUBSCRIPTION_STATE_EXPIRED', 'SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED'])
def test_non_entitled_states_never_activate_or_acknowledge(state):
    service, play, _, _ = service_fixture(acknowledged=False, state=state)
    snapshot = service.verify_purchase(firebase_uid='synthetic-a', purchase_token='synthetic-token-secret')
    assert snapshot.grants == ()
    assert play.acknowledgements == []


@pytest.mark.parametrize('state', ['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
    'SUBSCRIPTION_STATE_CANCELED'])
def test_active_grace_and_cancelled_unexpired_states_retain_access(state):
    service, _, _, _ = service_fixture(state=state)
    assert service.verify_purchase(firebase_uid='synthetic-a', purchase_token='synthetic-token-secret').grants


def test_acknowledgement_failure_keeps_recoverable_flag_and_retry_reverifies():
    service, play, documents, _ = service_fixture(acknowledged=False)
    def unavailable(**kwargs):
        raise RuntimeError('synthetic-sensitive-upstream-details')
    play.acknowledge = unavailable
    assert service.verify_purchase(firebase_uid='synthetic-a', purchase_token='synthetic-token-secret').acknowledgement_pending
    play.acknowledge = lambda **kwargs: None
    assert not service.verify_purchase(firebase_uid='synthetic-a', purchase_token='synthetic-token-secret').acknowledgement_pending
    assert 'synthetic-sensitive-upstream-details' not in repr(documents.values)


def test_trusted_notification_can_revoke_after_client_verification_budget_is_exhausted():
    service, play, _, clock = service_fixture()
    for _ in range(service.policy.verification_requests_per_minute):
        service.verify_purchase(firebase_uid='synthetic-a', purchase_token='synthetic-token-secret')
    with pytest.raises(BillingError, match='verification_rate_limited'):
        service.verify_purchase(firebase_uid='synthetic-a', purchase_token='synthetic-token-secret')
    assert len(play.verifications) == service.policy.verification_requests_per_minute
    play.result = VerifiedPlayPurchase('synthetic-premium', 'synthetic-monthly',
        service.account_identifier('synthetic-a'), 'SUBSCRIPTION_STATE_EXPIRED',
        clock[0], clock[0], True)
    assert service.refresh_notification(purchase_token='synthetic-token-secret')
    assert service.entitlements(firebase_uid='synthetic-a').grants == ()
    assert len(play.verifications) == service.policy.verification_requests_per_minute + 1


def test_verification_budget_outage_stops_before_refresh_or_play():
    service, play, documents, _ = service_fixture()
    refreshes = []
    def unavailable(**arguments):
        raise RuntimeError('synthetic-storage-unavailable')
    service.store.consume_verification_budget = unavailable
    service.store.begin_refresh = lambda **arguments: refreshes.append(arguments)
    with pytest.raises(BillingError, match='billing_unavailable'):
        service.verify_purchase(firebase_uid='synthetic-a', purchase_token='synthetic-token-secret')
    assert play.verifications == refreshes == []
    assert documents.values == {}


def test_managed_result_replay_does_not_call_provider_twice_or_charge_twice():
    service, _, documents, clock = service_fixture()
    service.verify_purchase(firebase_uid='synthetic-a', purchase_token='synthetic-token-secret')
    calls = []
    def generate():
        calls.append(1)
        return '{"text":"synthetic result"}'
    arguments = dict(firebase_uid='synthetic-a', request_id='synthetic-request-1',
        entitlement='managedContent', request_json='{"word":"synthetic"}', generate=generate)
    assert service.run_managed(**arguments) == '{"text":"synthetic result"}'
    clock[0] += timedelta(days=3)
    assert service.run_managed(**arguments) == '{"text":"synthetic result"}'
    assert calls == [1]
    assert next(value for path, value in documents.values.items()
        if path.startswith('billing_usage_windows/') and 'units' in value)['units'] == {'managedContent': 1}
    with pytest.raises(BillingError, match='request_conflict'):
        service.run_managed(**{**arguments, 'request_json': '{"word":"different"}'})


def test_provider_uncertain_outcome_is_never_automatically_submitted_again():
    service, _, _, _ = service_fixture()
    service.verify_purchase(firebase_uid='synthetic-a', purchase_token='synthetic-token-secret')
    calls = []
    def generate():
        calls.append(1)
        raise RuntimeError('synthetic-provider-submission-may-have-succeeded')
    for _ in range(2):
        with pytest.raises(BillingError, match='operation_uncertain'):
            service.run_managed(firebase_uid='synthetic-a', request_id='synthetic-request-1',
                entitlement='managedContent', request_json='{}', generate=generate)
    assert calls == [1]


def test_no_entitlement_or_quota_exhaustion_stops_before_provider_work():
    service, _, _, _ = service_fixture()
    calls = []
    arguments = dict(firebase_uid='synthetic-a', entitlement='managedContent', request_json='{}',
        generate=lambda: calls.append(1) or '{}')
    with pytest.raises(BillingError, match='entitlement_required'):
        service.run_managed(**arguments, request_id='before-purchase')
    assert calls == []
    service.verify_purchase(firebase_uid='synthetic-a', purchase_token='synthetic-token-secret')
    for request_id in ['first', 'second']:
        service.run_managed(**arguments, request_id=request_id)
    with pytest.raises(BillingError, match='quota_exhausted'):
        service.run_managed(**arguments, request_id='third')
    assert calls == [1, 1]


def test_owner_deletion_during_verification_creates_no_entitlement():
    service, play, documents, _ = service_fixture()
    original = play.verify
    def verifying(**kwargs):
        documents.values['account_deletion_operations/synthetic-a'] = {'synthetic': 'pending'}
        return original(**kwargs)
    play.verify = verifying
    with pytest.raises(BillingError, match='owner_deletion_pending'):
        service.verify_purchase(firebase_uid='synthetic-a', purchase_token='synthetic-token-secret')
    assert not any(path.startswith('billing_accounts/') for path in documents.values)
    assert not any(path.startswith('billing_purchases/') for path in documents.values)


@pytest.mark.parametrize('token', ['', 'a' * 4097, 'token\nsecret', None])
def test_invalid_token_is_rejected_before_storage_or_network(token):
    service, play, documents, _ = service_fixture()
    play.verify = lambda **kwargs: pytest.fail('network must not run')
    with pytest.raises(BillingError, match='invalid_request'):
        service.verify_purchase(firebase_uid='synthetic-a', purchase_token=token)
    assert documents.values == {}


def test_revocation_after_reservation_denies_before_provider_submission():
    service, play, _, _ = service_fixture()
    service.verify_purchase(firebase_uid='synthetic-a', purchase_token='synthetic-token-secret')
    service.store.reserve_usage(firebase_uid='synthetic-a', request_id='synthetic-reserved',
        payload_digest=hashlib.sha256(b'{}').hexdigest(), entitlement='managedContent', policy=POLICY, now_utc=NOW)
    play.result = VerifiedPlayPurchase('synthetic-premium', 'synthetic-monthly',
        service.account_identifier('synthetic-a'), 'SUBSCRIPTION_STATE_EXPIRED', NOW, NOW, True)
    service.verify_purchase(firebase_uid='synthetic-a', purchase_token='synthetic-token-secret')
    calls = []
    with pytest.raises(BillingError, match='entitlement_required'):
        service.run_managed(firebase_uid='synthetic-a', request_id='synthetic-reserved',
            entitlement='managedContent', request_json='{}', generate=lambda: calls.append(1) or '{}')
    assert calls == []


def test_failed_current_authority_refresh_suspends_an_existing_grant():
    service, play, _, _ = service_fixture()
    service.verify_purchase(firebase_uid='synthetic-a', purchase_token='synthetic-token-secret')
    def unavailable(**kwargs):
        raise BillingError('billing_unavailable')
    play.verify = unavailable
    with pytest.raises(BillingError, match='billing_unavailable'):
        service.verify_purchase(firebase_uid='synthetic-a', purchase_token='synthetic-token-secret')
    assert service.entitlements(firebase_uid='synthetic-a').grants == ()
    assert service.entitlements(firebase_uid='synthetic-a').refresh_required


def test_notification_never_claims_an_unknown_token_and_rechecks_known_purchase():
    service, play, documents, _ = service_fixture()
    assert not service.refresh_notification(purchase_token='synthetic-unknown-token')
    assert documents.values == {}
    assert play.verifications == []
    service.verify_purchase(firebase_uid='synthetic-a', purchase_token='synthetic-token-secret')
    play.result = VerifiedPlayPurchase('synthetic-premium', 'synthetic-monthly',
        service.account_identifier('synthetic-a'), 'SUBSCRIPTION_STATE_EXPIRED', NOW, NOW, True)
    for _ in range(2):
        assert service.refresh_notification(purchase_token='synthetic-token-secret')
    assert len(play.verifications) == 3
    assert service.entitlements(firebase_uid='synthetic-a').grants == ()


def test_disabled_service_builder_never_initializes_external_adapters(monkeypatch):
    from lexiquest_ai.billing import build_billing_service
    from lexiquest_ai.config import Settings
    from lexiquest_ai.play_billing import GooglePlayTransport
    monkeypatch.setattr(GooglePlayTransport, 'production', lambda: pytest.fail('disabled must not load credentials'))
    assert build_billing_service(Settings()) is None
