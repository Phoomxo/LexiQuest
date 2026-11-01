from __future__ import annotations

import hashlib
import re
import uuid
from collections.abc import Callable, Mapping
from datetime import datetime, timedelta
from typing import Protocol, TypeVar

from firebase_admin import firestore as firebase_firestore
from google.cloud import firestore as google_firestore

from lexiquest_ai.billing import (
    BillingError, BillingPolicy, EntitlementGrant, EntitlementSnapshot,
    PurchaseRefresh, UsageReservation, VerifiedPlayPurchase, canonical_json,
    require_code, require_uid, require_utc,
)

T = TypeVar('T')
Document = dict[str, object]
DocumentsUpdate = Callable[[Mapping[str, Document | None]], tuple[dict[str, Document | None], T]]


class AtomicBillingDocuments(Protocol):
    def transact(self, paths: tuple[str, ...], update: DocumentsUpdate[T]) -> T: ...


class FirestoreBillingDocuments:
    def __init__(self, client=None) -> None:
        self._client = client if client is not None else firebase_firestore.client()

    def transact(self, paths: tuple[str, ...], update: DocumentsUpdate[T]) -> T:
        refs = {path: self._client.document(path) for path in paths}
        transaction = self._client.transaction()

        @google_firestore.transactional
        def run(current_transaction):
            current = {}
            for path, ref in refs.items():
                snapshot = ref.get(transaction=current_transaction)
                current[path] = snapshot.to_dict() if snapshot.exists else None
            writes, result = update(current)
            if not writes.keys() <= refs.keys():
                raise BillingError('billing_unavailable')
            for path, value in writes.items():
                if value is None:
                    current_transaction.delete(refs[path])
                else:
                    current_transaction.set(refs[path], value)
            return result

        return run(transaction)


class FirestoreBillingStore:
    def __init__(self, documents: AtomicBillingDocuments):
        self._documents = documents

    @classmethod
    def production(cls) -> FirestoreBillingStore:
        return cls(FirestoreBillingDocuments())

    def owner_for_token(self, token_fingerprint: str) -> str | None:
        path = _purchase_path(token_fingerprint)

        def read(current):
            record = current[path]
            if record is None or 'purchase' not in record:
                return {}, None
            return {}, require_uid(_map(record['purchase']).get('firebaseUid'))

        return self._documents.transact((path,), read)

    def consume_verification_budget(self, *, firebase_uid: str, policy: BillingPolicy,
                                    now_utc: datetime) -> None:
        require_uid(firebase_uid)
        now = require_utc(now_utc)
        window = now.replace(second=0, microsecond=0)
        counter, fence = _counter_path(firebase_uid, 'purchase-verification'), _fence(firebase_uid)

        def update(current):
            _unfenced(current[fence])
            previous = current[counter]
            used = 0
            if previous is not None:
                if previous.get('firebaseUid') != firebase_uid or previous.get('purpose') != 'purchaseVerification':
                    raise BillingError('billing_unavailable')
                started = _utc_field(previous, 'windowStartedAtUtc')
                attempts = previous.get('attempts')
                if type(attempts) is not int or not 1 <= attempts <= 120 or started > window:
                    raise BillingError('billing_unavailable')
                if started == window:
                    used = attempts
            if used >= policy.verification_requests_per_minute:
                raise BillingError('verification_rate_limited')
            return {counter: {'firebaseUid': firebase_uid, 'purpose': 'purchaseVerification',
                'windowStartedAtUtc': window, 'attempts': used + 1}}, None

        self._documents.transact((counter, fence), update)

    def begin_refresh(self, *, firebase_uid: str, token_fingerprint: str,
                      now_utc: datetime) -> PurchaseRefresh:
        require_uid(firebase_uid)
        _fingerprint(token_fingerprint)
        require_utc(now_utc)
        path, fence = _purchase_path(token_fingerprint), _fence(firebase_uid)
        lease_id = uuid.uuid4().hex

        def update(current):
            _unfenced(current[fence])
            record = current[path] or {}
            purchase = record.get('purchase')
            if purchase is not None and _map(purchase).get('firebaseUid') != firebase_uid:
                raise BillingError('owner_mismatch')
            lease = record.get('lease')
            if lease is not None and _utc_field(_map(lease), 'expiresAtUtc') > now_utc:
                raise BillingError('purchase_refresh_pending')
            expires = now_utc + timedelta(seconds=30)
            result = PurchaseRefresh(token_fingerprint, firebase_uid, lease_id, expires)
            return {path: {**record, 'firebaseUid': firebase_uid, 'lease': {'id': lease_id, 'firebaseUid': firebase_uid,
                'startedAtUtc': now_utc, 'expiresAtUtc': expires}}}, result

        return self._documents.transact((path, fence), update)

    def abort_refresh(self, refresh: PurchaseRefresh) -> None:
        path = _purchase_path(refresh.token_fingerprint)
        account, fence = _account_path(refresh.firebase_uid), _fence(refresh.firebase_uid)

        def update(current):
            record = current[path]
            if record is None or _map(record.get('lease', {})).get('id') != refresh.lease_id:
                return {}, None
            if 'purchase' not in record:
                return {path: None}, None
            previous = _map(record['purchase'])
            if current[fence] is not None:
                return {path: {'firebaseUid': refresh.firebase_uid, 'purchase': previous}}, None
            if previous.get('firebaseUid') != refresh.firebase_uid:
                raise BillingError('owner_mismatch')
            owner = _account(current[account], refresh.firebase_uid)
            purchases = dict(_map(owner['purchases']))
            if purchases.get(refresh.token_fingerprint) != previous:
                raise BillingError('billing_unavailable')
            suspended = {**previous, 'revision': _positive(previous.get('revision')) + 1,
                'state': 'AUTHORITY_UNAVAILABLE', 'acknowledgementPending': False}
            purchases[refresh.token_fingerprint] = suspended
            return {path: {'firebaseUid': refresh.firebase_uid, 'purchase': suspended},
                account: {'firebaseUid': refresh.firebase_uid, 'purchases': purchases}}, None

        self._documents.transact((path, account, fence), update)

    def commit_refresh(self, refresh: PurchaseRefresh, purchase: VerifiedPlayPurchase,
                       policy: BillingPolicy, now_utc: datetime) -> int:
        require_utc(now_utc)
        require_utc(purchase.checked_at_utc)
        require_utc(purchase.expires_at_utc)
        policy.product(purchase.product_id, purchase.base_plan_id)
        if type(purchase.acknowledged) is not bool or purchase.checked_at_utc > now_utc:
            raise BillingError('purchase_denied')
        path, account, fence = (_purchase_path(refresh.token_fingerprint),
            _account_path(refresh.firebase_uid), _fence(refresh.firebase_uid))

        def update(current):
            _unfenced(current[fence])
            record = current[path]
            if record is None or not isinstance(record.get('lease'), dict):
                raise BillingError('authority_changed')
            lease = _map(record.get('lease'))
            if (lease.get('id') != refresh.lease_id or lease.get('firebaseUid') != refresh.firebase_uid
                    or _utc_field(lease, 'expiresAtUtc') <= now_utc
                    or purchase.checked_at_utc < _utc_field(lease, 'startedAtUtc')):
                raise BillingError('authority_changed')
            previous = _map(record['purchase']) if 'purchase' in record else None
            if previous is not None and previous.get('firebaseUid') != refresh.firebase_uid:
                raise BillingError('owner_mismatch')
            revision = 1 if previous is None else _positive(previous.get('revision')) + 1
            value = {'firebaseUid': refresh.firebase_uid, 'revision': revision,
                'policyRevision': policy.revision, 'productId': purchase.product_id,
                'basePlanId': purchase.base_plan_id, 'state': purchase.state,
                'expiresAtUtc': purchase.expires_at_utc, 'checkedAtUtc': purchase.checked_at_utc,
                'acknowledgementPending': purchase.permits_access and not purchase.acknowledged}
            owner = _account(current[account], refresh.firebase_uid)
            purchases = dict(_map(owner['purchases']))
            if refresh.token_fingerprint not in purchases and len(purchases) >= 64:
                raise BillingError('billing_unavailable')
            purchases[refresh.token_fingerprint] = value
            return {path: {'firebaseUid': refresh.firebase_uid, 'purchase': value}, account: {'firebaseUid': refresh.firebase_uid,
                'purchases': purchases}}, revision

        return self._documents.transact((path, account, fence), update)

    def mark_acknowledged(self, *, firebase_uid: str, token_fingerprint: str,
                          revision: int, now_utc: datetime) -> None:
        path, account, fence = _purchase_path(token_fingerprint), _account_path(firebase_uid), _fence(firebase_uid)
        require_utc(now_utc)

        def update(current):
            _unfenced(current[fence])
            record = current[path]
            if record is None:
                raise BillingError('authority_changed')
            purchase = _map(record.get('purchase'))
            if purchase.get('firebaseUid') != firebase_uid or purchase.get('revision') != revision:
                raise BillingError('authority_changed')
            owner = _account(current[account], firebase_uid)
            purchases = dict(_map(owner['purchases']))
            if purchases.get(token_fingerprint) != purchase:
                raise BillingError('billing_unavailable')
            updated = {**purchase, 'acknowledgementPending': False}
            purchases[token_fingerprint] = updated
            return {path: {**record, 'purchase': updated}, account: {
                'firebaseUid': firebase_uid, 'purchases': purchases}}, None

        self._documents.transact((path, account, fence), update)

    def snapshot(self, *, firebase_uid: str, policy: BillingPolicy, now_utc: datetime) -> EntitlementSnapshot:
        account, fence = _account_path(firebase_uid), _fence(firebase_uid)
        require_utc(now_utc)

        def read(current):
            _unfenced(current[fence])
            return {}, _snapshot(current[account], firebase_uid, policy, now_utc)

        return self._documents.transact((account, fence), read)

    def reserve_usage(self, *, firebase_uid: str, request_id: str, payload_digest: str,
                      entitlement: str, policy: BillingPolicy, now_utc: datetime) -> UsageReservation:
        require_uid(firebase_uid)
        require_code(request_id)
        require_code(entitlement)
        _fingerprint(payload_digest)
        require_utc(now_utc)
        window = now_utc.strftime('%Y-%m-%d')
        operation, counter = _usage_path(firebase_uid, request_id), _counter_path(firebase_uid, window)
        account, fence = _account_path(firebase_uid), _fence(firebase_uid)

        def update(current):
            _unfenced(current[fence])
            if current[operation] is not None:
                existing = _usage(current[operation], firebase_uid, request_id)
                if existing.payload_digest != payload_digest or existing.entitlement != entitlement:
                    raise BillingError('request_conflict')
                return {}, existing
            grant = _snapshot(current[account], firebase_uid, policy, now_utc).grant(entitlement)
            counts = current[counter] or {'firebaseUid': firebase_uid, 'window': window, 'units': {}}
            if counts.get('firebaseUid') != firebase_uid or counts.get('window') != window:
                raise BillingError('billing_unavailable')
            units = dict(_map(counts.get('units')))
            used = units.get(entitlement, 0)
            if type(used) is not int or used < 0:
                raise BillingError('billing_unavailable')
            if used >= grant.daily_managed_units:
                raise BillingError('quota_exhausted')
            units[entitlement] = used + 1
            value = {'firebaseUid': firebase_uid, 'requestId': request_id, 'payloadDigest': payload_digest,
                'entitlement': entitlement, 'state': 'reserved', 'window': window,
                'policyRevision': policy.revision, 'createdAtUtc': now_utc, 'responseJson': None}
            return {operation: value, counter: {**counts, 'units': units}}, _usage(value, firebase_uid, request_id)

        return self._documents.transact((operation, counter, account, fence), update)

    def submit_usage(self, reservation: UsageReservation, *, policy: BillingPolicy,
                     now_utc: datetime) -> UsageReservation:
        return self._transition_usage(reservation, state='submitted', response_json=None,
            now_utc=now_utc, policy=policy)

    def finish_usage(self, reservation: UsageReservation, *, response_json: str | None,
                     now_utc: datetime) -> UsageReservation:
        result = None if response_json is None else canonical_json(response_json)
        return self._transition_usage(reservation,
            state='uncertain' if result is None else 'completed', response_json=result, now_utc=now_utc)

    def _transition_usage(self, reservation: UsageReservation, *, state: str,
                          response_json: str | None, now_utc: datetime,
                          policy: BillingPolicy | None = None) -> UsageReservation:
        require_utc(now_utc)
        operation = _usage_path(reservation.firebase_uid, reservation.request_id)
        fence = _fence(reservation.firebase_uid)
        account = _account_path(reservation.firebase_uid)

        def update(current):
            _unfenced(current[fence])
            value = current[operation]
            existing = _usage(value, reservation.firebase_uid, reservation.request_id)
            if (existing.payload_digest, existing.entitlement, existing.window) != (
                    reservation.payload_digest, reservation.entitlement, reservation.window):
                raise BillingError('request_conflict')
            if state in {'completed', 'uncertain'} and existing.state == state and existing.response_json == response_json:
                return {}, existing
            required = 'reserved' if state == 'submitted' else 'submitted'
            if existing.state != required or reservation.state != required:
                raise BillingError('operation_uncertain')
            if state == 'submitted':
                if policy is None or value.get('policyRevision') != policy.revision:
                    raise BillingError('authority_changed')
                _snapshot(current[account], reservation.firebase_uid, policy, now_utc).grant(reservation.entitlement)
            updated = {**value, 'state': state, 'updatedAtUtc': now_utc, 'responseJson': response_json}
            return {operation: updated}, _usage(updated, reservation.firebase_uid, reservation.request_id)

        return self._documents.transact((operation, fence, account), update)


def _snapshot(document, uid: str, policy: BillingPolicy, now: datetime) -> EntitlementSnapshot:
    account = _account(document, uid)
    grants = []
    pending = False
    refresh_required = False
    for fingerprint, raw in _map(account['purchases']).items():
        _fingerprint(fingerprint)
        purchase = _map(raw)
        if purchase.get('firebaseUid') != uid:
            raise BillingError('billing_unavailable')
        _positive(purchase.get('revision'))
        checked = _utc_field(purchase, 'checkedAtUtc')
        expiry = _utc_field(purchase, 'expiresAtUtc')
        if type(purchase.get('acknowledgementPending')) is not bool:
            raise BillingError('billing_unavailable')
        current = timedelta(0) <= now - checked <= policy.authority_max_age
        if expiry > now and (purchase.get('policyRevision') != policy.revision or not current
                or purchase.get('state') == 'AUTHORITY_UNAVAILABLE'):
            refresh_required = True
        if (purchase.get('policyRevision') != policy.revision or not current
                or expiry <= now or purchase.get('state') not in {
                    'SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD', 'SUBSCRIPTION_STATE_CANCELED'}):
            continue
        product = policy.product(purchase.get('productId'), purchase.get('basePlanId'))
        pending = pending or purchase['acknowledgementPending']
        grants.extend(EntitlementGrant(right, expiry, checked, product.daily_managed_units) for right in sorted(product.entitlements))
    return EntitlementSnapshot(now, tuple(grants), pending, refresh_required)


def _account(document, uid: str) -> Document:
    if document is None:
        return {'firebaseUid': uid, 'purchases': {}}
    if not isinstance(document, dict) or document.get('firebaseUid') != uid or len(_map(document.get('purchases'))) > 64:
        raise BillingError('billing_unavailable')
    return document


def _usage(document, uid: str, request_id: str) -> UsageReservation:
    value = _map(document)
    if value.get('firebaseUid') != uid or value.get('requestId') != request_id or value.get('state') not in {'reserved', 'submitted', 'completed', 'uncertain'}:
        raise BillingError('billing_unavailable')
    digest, right, window = value.get('payloadDigest'), value.get('entitlement'), value.get('window')
    _fingerprint(digest)
    require_code(right)
    if not isinstance(window, str) or re.fullmatch(r'\d{4}-\d{2}-\d{2}', window) is None:
        raise BillingError('billing_unavailable')
    response = value.get('responseJson')
    if value['state'] == 'completed':
        response = canonical_json(response)
    elif response is not None:
        raise BillingError('billing_unavailable')
    return UsageReservation(uid, request_id, digest, right, value['state'], window, response)


def _map(value) -> Document:
    if not isinstance(value, dict):
        raise BillingError('billing_unavailable')
    return value


def _utc_field(value: Document, key: str) -> datetime:
    return require_utc(value.get(key))


def _positive(value) -> int:
    if type(value) is not int or not 1 <= value < 2**53:
        raise BillingError('billing_unavailable')
    return value


def _fingerprint(value: str) -> str:
    if not isinstance(value, str) or re.fullmatch('[0-9a-f]{64}', value) is None:
        raise BillingError('invalid_request')
    return value


def _purchase_path(fingerprint: str) -> str:
    return f'billing_purchases/{_fingerprint(fingerprint)}'


def _account_path(uid: str) -> str:
    return f'billing_accounts/{require_uid(uid)}'


def _fence(uid: str) -> str:
    return f'account_deletion_operations/{require_uid(uid)}'


def _usage_path(uid: str, request_id: str) -> str:
    require_uid(uid)
    require_code(request_id)
    return 'billing_usage/' + hashlib.sha256(f'{uid}\0{request_id}'.encode()).hexdigest()


def _counter_path(uid: str, window: str) -> str:
    return 'billing_usage_windows/' + hashlib.sha256(f'{uid}\0{window}'.encode()).hexdigest()


def _unfenced(value) -> None:
    if value is not None:
        raise BillingError('owner_deletion_pending')
