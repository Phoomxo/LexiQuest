import copy
import threading
from dataclasses import replace
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta

import pytest

from lexiquest_ai.billing import BillingError, BillingPolicy, BillingProduct, VerifiedPlayPurchase
from lexiquest_ai.firestore_billing import FirestoreBillingStore
from lexiquest_ai.firestore_billing import FirestoreBillingDocuments
from types import SimpleNamespace
import lexiquest_ai.firestore_billing as firestore_adapter


NOW = datetime(2026, 11, 1, tzinfo=UTC)
POLICY = BillingPolicy('com.lexiquest.app', 'synthetic-v1', (
    BillingProduct('synthetic-premium', 'synthetic-monthly', frozenset({'managedContent'}), 1),
))


class Documents:
    def __init__(self):
        self.values = {}
        self.lock = threading.Lock()

    def transact(self, paths, update):
        with self.lock:
            current = {path: copy.deepcopy(self.values.get(path)) for path in paths}
            writes, result = update(current)
            for path, value in writes.items():
                assert path in paths
                if value is None:
                    self.values.pop(path, None)
                else:
                    self.values[path] = copy.deepcopy(value)
            return result


def purchase(state='SUBSCRIPTION_STATE_ACTIVE', acknowledged=True):
    return VerifiedPlayPurchase('synthetic-premium', 'synthetic-monthly', 'a' * 64,
        state, NOW + timedelta(days=2), NOW, acknowledged)


def test_verification_budget_is_atomic_across_instances_and_separate_from_paid_quota():
    documents = Documents()
    stores = [FirestoreBillingStore(documents) for _ in range(24)]
    policy = replace(POLICY, verification_requests_per_minute=3)
    def attempt(index):
        try:
            stores[index].consume_verification_budget(firebase_uid='synthetic-a', policy=policy, now_utc=NOW)
            return 'allowed'
        except BillingError as error:
            return error.code
    with ThreadPoolExecutor(max_workers=8) as executor:
        results = list(executor.map(attempt, range(24)))
    assert results.count('allowed') == 3
    assert results.count('verification_rate_limited') == 21
    assert len(documents.values) == 1
    counter = next(iter(documents.values.values()))
    assert counter['attempts'] == 3
    assert counter['purpose'] == 'purchaseVerification'
    assert 'units' not in counter


def test_verification_budget_resets_next_minute_is_owner_scoped_and_rejects_clock_rollback():
    documents = Documents()
    store = FirestoreBillingStore(documents)
    policy = replace(POLICY, verification_requests_per_minute=1)
    store.consume_verification_budget(firebase_uid='synthetic-a', policy=policy, now_utc=NOW)
    before = copy.deepcopy(documents.values)
    with pytest.raises(BillingError, match='verification_rate_limited'):
        store.consume_verification_budget(firebase_uid='synthetic-a', policy=policy, now_utc=NOW + timedelta(seconds=59))
    assert documents.values == before
    store.consume_verification_budget(firebase_uid='synthetic-b', policy=policy, now_utc=NOW)
    store.consume_verification_budget(firebase_uid='synthetic-a', policy=policy, now_utc=NOW + timedelta(minutes=1))
    assert len(documents.values) == 2
    assert all(value['attempts'] == 1 for value in documents.values.values())
    after = copy.deepcopy(documents.values)
    with pytest.raises(BillingError, match='billing_unavailable'):
        store.consume_verification_budget(firebase_uid='synthetic-a', policy=policy, now_utc=NOW)
    assert documents.values == after


def test_verification_budget_respects_deletion_fence_without_writing_a_counter():
    documents = Documents()
    documents.values['account_deletion_operations/synthetic-a'] = {'state': 'deleting'}
    before = copy.deepcopy(documents.values)
    with pytest.raises(BillingError, match='owner_deletion_pending'):
        FirestoreBillingStore(documents).consume_verification_budget(
            firebase_uid='synthetic-a', policy=POLICY, now_utc=NOW)
    assert documents.values == before


def test_token_bound_to_a_cannot_be_restored_by_b():
    documents = Documents()
    store = FirestoreBillingStore(documents)
    refresh = store.begin_refresh(firebase_uid='synthetic-a', token_fingerprint='a' * 64, now_utc=NOW)
    store.commit_refresh(refresh, purchase(), POLICY, NOW)
    before = copy.deepcopy(documents.values)

    with pytest.raises(BillingError, match='owner_mismatch'):
        store.begin_refresh(firebase_uid='synthetic-b', token_fingerprint='a' * 64, now_utc=NOW)

    assert documents.values == before


def entitled_store():
    documents = Documents()
    store = FirestoreBillingStore(documents)
    refresh = store.begin_refresh(firebase_uid='synthetic-a', token_fingerprint='a' * 64, now_utc=NOW)
    store.commit_refresh(refresh, purchase(), POLICY, NOW)
    return store, documents


def test_only_one_concurrent_last_quota_reservation_succeeds():
    store, documents = entitled_store()
    def reserve(index):
        try:
            return store.reserve_usage(firebase_uid='synthetic-a', request_id=f'synthetic-{index}',
                payload_digest='a' * 64, entitlement='managedContent', policy=POLICY, now_utc=NOW).state
        except BillingError as error:
            return error.code
    with ThreadPoolExecutor(max_workers=8) as executor:
        results = list(executor.map(reserve, range(8)))
    assert results.count('reserved') == 1
    assert results.count('quota_exhausted') == 7
    assert len([path for path in documents.values if path.startswith('billing_usage/')]) == 1


def test_old_refresh_cannot_overwrite_newer_revocation_after_lease_expiry():
    store, _ = entitled_store()
    old = store.begin_refresh(firebase_uid='synthetic-a', token_fingerprint='a' * 64, now_utc=NOW)
    later = NOW + timedelta(seconds=31)
    current = store.begin_refresh(firebase_uid='synthetic-a', token_fingerprint='a' * 64, now_utc=later)
    revoked = VerifiedPlayPurchase('synthetic-premium', 'synthetic-monthly', 'a' * 64,
        'SUBSCRIPTION_STATE_EXPIRED', NOW, later, True)
    store.commit_refresh(current, revoked, POLICY, later)
    with pytest.raises(BillingError, match='authority_changed'):
        store.commit_refresh(old, purchase(), POLICY, later)
    assert store.snapshot(firebase_uid='synthetic-a', policy=POLICY, now_utc=later).grants == ()


def test_active_refresh_lease_rejects_parallel_verification_until_expiry():
    store, _ = entitled_store()
    store.begin_refresh(firebase_uid='synthetic-a', token_fingerprint='a' * 64, now_utc=NOW)
    with pytest.raises(BillingError, match='purchase_refresh_pending'):
        store.begin_refresh(firebase_uid='synthetic-a', token_fingerprint='a' * 64, now_utc=NOW)


def test_stale_or_expired_authority_cannot_reserve_new_usage():
    store, _ = entitled_store()
    stale = NOW + timedelta(minutes=6)
    assert store.snapshot(firebase_uid='synthetic-a', policy=POLICY, now_utc=stale).grants == ()
    assert store.snapshot(firebase_uid='synthetic-a', policy=POLICY, now_utc=stale).refresh_required
    with pytest.raises(BillingError, match='entitlement_required'):
        store.reserve_usage(firebase_uid='synthetic-a', request_id='stale', payload_digest='a' * 64,
            entitlement='managedContent', policy=POLICY, now_utc=stale)


def test_deletion_fence_blocks_snapshot_reservation_and_replay():
    store, documents = entitled_store()
    reservation = store.reserve_usage(firebase_uid='synthetic-a', request_id='first',
        payload_digest='a' * 64, entitlement='managedContent', policy=POLICY, now_utc=NOW)
    documents.values['account_deletion_operations/synthetic-a'] = {'synthetic': True}
    for call in [
        lambda: store.snapshot(firebase_uid='synthetic-a', policy=POLICY, now_utc=NOW),
        lambda: store.submit_usage(reservation, policy=POLICY, now_utc=NOW),
        lambda: store.reserve_usage(firebase_uid='synthetic-a', request_id='first', payload_digest='a' * 64,
            entitlement='managedContent', policy=POLICY, now_utc=NOW),
    ]:
        with pytest.raises(BillingError, match='owner_deletion_pending'):
            call()


def test_revoking_one_purchase_does_not_remove_another_current_purchase():
    store, _ = entitled_store()
    second = store.begin_refresh(firebase_uid='synthetic-a', token_fingerprint='b' * 64, now_utc=NOW)
    store.commit_refresh(second, purchase(), POLICY, NOW)
    first = store.begin_refresh(firebase_uid='synthetic-a', token_fingerprint='a' * 64, now_utc=NOW)
    store.commit_refresh(first, purchase('SUBSCRIPTION_STATE_EXPIRED'), POLICY, NOW)
    assert store.snapshot(firebase_uid='synthetic-a', policy=POLICY, now_utc=NOW).grant('managedContent')


def test_submitted_operation_cannot_be_submitted_twice_even_with_same_request():
    store, _ = entitled_store()
    reservation = store.reserve_usage(firebase_uid='synthetic-a', request_id='first',
        payload_digest='a' * 64, entitlement='managedContent', policy=POLICY, now_utc=NOW)
    submitted = store.submit_usage(reservation, policy=POLICY, now_utc=NOW)
    with pytest.raises(BillingError, match='operation_uncertain'):
        store.submit_usage(reservation, policy=POLICY, now_utc=NOW)
    assert submitted.state == 'submitted'


def test_firestore_sdk_adapter_passes_real_reads_and_atomic_writes_to_the_transaction(monkeypatch):
    values = {}
    class Ref:
        def __init__(self, path):
            self.path = path
        def get(self, *, transaction):
            assert not transaction.writes, 'all reads precede transaction writes'
            value = copy.deepcopy(values.get(self.path))
            return SimpleNamespace(exists=value is not None, to_dict=lambda: value)
    class Transaction:
        def __init__(self):
            self.writes = {}
        def set(self, ref, value):
            self.writes[ref.path] = value
        def delete(self, ref):
            self.writes[ref.path] = None
    def transactional(function):
        def run(transaction):
            result = function(transaction)
            for path, value in transaction.writes.items():
                if value is None:
                    values.pop(path, None)
                else:
                    values[path] = copy.deepcopy(value)
            return result
        return run
    monkeypatch.setattr(firestore_adapter.google_firestore, 'transactional', transactional)
    documents = FirestoreBillingDocuments(SimpleNamespace(document=Ref, transaction=Transaction))
    store = FirestoreBillingStore(documents)
    store.consume_verification_budget(firebase_uid='synthetic-a', policy=POLICY, now_utc=NOW)
    refresh = store.begin_refresh(firebase_uid='synthetic-a', token_fingerprint='a' * 64, now_utc=NOW)
    store.commit_refresh(refresh, purchase(), POLICY, NOW)
    assert store.snapshot(firebase_uid='synthetic-a', policy=POLICY, now_utc=NOW).grants
    assert len(values) == 3
    before = copy.deepcopy(values)
    with pytest.raises(BillingError, match='billing_unavailable'):
        documents.transact(('billing_accounts/synthetic-a',), lambda _: ({'other/forbidden': {}}, None))
    assert values == before
