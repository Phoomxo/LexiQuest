from __future__ import annotations

import hashlib
import hmac
import json
import re
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Protocol


class BillingError(Exception):
    def __init__(self, code: str) -> None:
        self.code = code
        super().__init__(code)


@dataclass(frozen=True, slots=True)
class BillingProduct:
    product_id: str
    base_plan_id: str
    entitlements: frozenset[str]
    daily_managed_units: int

    def __post_init__(self) -> None:
        for value in (self.product_id, self.base_plan_id, *self.entitlements):
            require_code(value)
        if not self.entitlements or len(self.entitlements) > 32:
            raise BillingError('invalid_configuration')
        if type(self.daily_managed_units) is not int or not 0 <= self.daily_managed_units <= 1_000_000:
            raise BillingError('invalid_configuration')


@dataclass(frozen=True, slots=True)
class BillingPolicy:
    package_name: str
    revision: str
    products: tuple[BillingProduct, ...]
    authority_max_age: timedelta = timedelta(minutes=5)
    verification_requests_per_minute: int = 20

    def __post_init__(self) -> None:
        require_code(self.package_name)
        require_code(self.revision)
        keys = [(product.product_id, product.base_plan_id) for product in self.products]
        if not keys or len(keys) != len(set(keys)) or not timedelta(0) < self.authority_max_age <= timedelta(hours=1):
            raise BillingError('invalid_configuration')
        if type(self.verification_requests_per_minute) is not int or not 1 <= self.verification_requests_per_minute <= 120:
            raise BillingError('invalid_configuration')

    def product(self, product_id: str, base_plan_id: str) -> BillingProduct:
        for product in self.products:
            if (product.product_id, product.base_plan_id) == (product_id, base_plan_id):
                return product
        raise BillingError('purchase_denied')


@dataclass(frozen=True, slots=True)
class VerifiedPlayPurchase:
    product_id: str
    base_plan_id: str
    obfuscated_account_id: str
    state: str
    expires_at_utc: datetime
    checked_at_utc: datetime
    acknowledged: bool

    @property
    def permits_access(self) -> bool:
        return self.state in {
            'SUBSCRIPTION_STATE_ACTIVE',
            'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
            'SUBSCRIPTION_STATE_CANCELED',
        } and self.expires_at_utc > self.checked_at_utc


@dataclass(frozen=True, slots=True)
class PurchaseRefresh:
    token_fingerprint: str
    firebase_uid: str
    lease_id: str
    expires_at_utc: datetime


@dataclass(frozen=True, slots=True)
class EntitlementGrant:
    entitlement: str
    expires_at_utc: datetime
    checked_at_utc: datetime
    daily_managed_units: int


@dataclass(frozen=True, slots=True)
class EntitlementSnapshot:
    checked_at_utc: datetime
    grants: tuple[EntitlementGrant, ...]
    acknowledgement_pending: bool = False
    refresh_required: bool = False

    def grant(self, entitlement: str) -> EntitlementGrant:
        candidates = [grant for grant in self.grants if grant.entitlement == entitlement]
        if not candidates:
            raise BillingError('entitlement_required')
        return max(candidates, key=lambda grant: (grant.daily_managed_units, grant.expires_at_utc))


@dataclass(frozen=True, slots=True)
class UsageReservation:
    firebase_uid: str
    request_id: str
    payload_digest: str
    entitlement: str
    state: str
    window: str
    response_json: str | None = None


class PlayPurchaseVerifier(Protocol):
    def verify(self, *, package_name: str, purchase_token: str, policy: BillingPolicy,
               checked_at_utc: datetime) -> VerifiedPlayPurchase: ...

    def acknowledge(self, *, package_name: str, product_id: str, purchase_token: str) -> None: ...


class BillingStore(Protocol):
    def owner_for_token(self, token_fingerprint: str) -> str | None: ...
    def consume_verification_budget(self, *, firebase_uid: str, policy: BillingPolicy,
                                    now_utc: datetime) -> None: ...
    def begin_refresh(self, *, firebase_uid: str, token_fingerprint: str, now_utc: datetime) -> PurchaseRefresh: ...
    def abort_refresh(self, refresh: PurchaseRefresh) -> None: ...
    def commit_refresh(self, refresh: PurchaseRefresh, purchase: VerifiedPlayPurchase,
                       policy: BillingPolicy, now_utc: datetime) -> int: ...
    def mark_acknowledged(self, *, firebase_uid: str, token_fingerprint: str,
                          revision: int, now_utc: datetime) -> None: ...
    def snapshot(self, *, firebase_uid: str, policy: BillingPolicy, now_utc: datetime) -> EntitlementSnapshot: ...
    def reserve_usage(self, *, firebase_uid: str, request_id: str, payload_digest: str,
                      entitlement: str, policy: BillingPolicy, now_utc: datetime) -> UsageReservation: ...
    def submit_usage(self, reservation: UsageReservation, *, policy: BillingPolicy,
                     now_utc: datetime) -> UsageReservation: ...
    def finish_usage(self, reservation: UsageReservation, *, response_json: str | None,
                     now_utc: datetime) -> UsageReservation: ...


class BillingService:
    def __init__(self, *, policy: BillingPolicy, play: PlayPurchaseVerifier,
                 store: BillingStore, account_binding_key: bytes,
                 now_utc: Callable[[], datetime]):
        if not isinstance(account_binding_key, bytes) or len(account_binding_key) < 32:
            raise BillingError('invalid_configuration')
        self.policy = policy
        self.play = play
        self.store = store
        self._account_binding_key = account_binding_key
        self._now_utc = now_utc

    def account_identifier(self, firebase_uid: str) -> str:
        require_uid(firebase_uid)
        return hmac.new(self._account_binding_key, firebase_uid.encode(), hashlib.sha256).hexdigest()

    def verify_purchase(self, *, firebase_uid: str, purchase_token: str) -> EntitlementSnapshot:
        require_uid(firebase_uid)
        require_purchase_token(purchase_token)
        try:
            self.store.consume_verification_budget(firebase_uid=firebase_uid,
                policy=self.policy, now_utc=self._now())
        except BillingError:
            raise
        except Exception:
            raise BillingError('billing_unavailable') from None
        return self._verify_purchase(firebase_uid=firebase_uid, purchase_token=purchase_token)

    def _verify_purchase(self, *, firebase_uid: str, purchase_token: str) -> EntitlementSnapshot:
        fingerprint = hashlib.sha256(purchase_token.encode()).hexdigest()
        refresh = self.store.begin_refresh(firebase_uid=firebase_uid,
            token_fingerprint=fingerprint, now_utc=self._now())
        try:
            purchase = self.play.verify(package_name=self.policy.package_name,
                purchase_token=purchase_token, policy=self.policy, checked_at_utc=self._now())
            if not hmac.compare_digest(purchase.obfuscated_account_id, self.account_identifier(firebase_uid)):
                raise BillingError('owner_mismatch')
            self.policy.product(purchase.product_id, purchase.base_plan_id)
            revision = self.store.commit_refresh(refresh, purchase, self.policy, self._now())
        except Exception as error:
            self.store.abort_refresh(refresh)
            if isinstance(error, BillingError):
                raise
            raise BillingError('billing_unavailable') from None
        if purchase.permits_access and not purchase.acknowledged:
            try:
                self.play.acknowledge(package_name=self.policy.package_name,
                    product_id=purchase.product_id, purchase_token=purchase_token)
                self.store.mark_acknowledged(firebase_uid=firebase_uid,
                    token_fingerprint=fingerprint, revision=revision, now_utc=self._now())
            except Exception:
                pass
        return self.entitlements(firebase_uid=firebase_uid)

    def entitlements(self, *, firebase_uid: str) -> EntitlementSnapshot:
        require_uid(firebase_uid)
        return self.store.snapshot(firebase_uid=firebase_uid, policy=self.policy, now_utc=self._now())

    def refresh_notification(self, *, purchase_token: str) -> bool:
        require_purchase_token(purchase_token)
        owner = self.store.owner_for_token(hashlib.sha256(purchase_token.encode()).hexdigest())
        if owner is None:
            return False
        try:
            self._verify_purchase(firebase_uid=owner, purchase_token=purchase_token)
        except BillingError as error:
            if error.code != 'purchase_denied':
                raise
        return True

    def run_managed(self, *, firebase_uid: str, request_id: str, entitlement: str,
                    request_json: str, generate: Callable[[], str]) -> str:
        require_uid(firebase_uid)
        require_code(request_id)
        require_code(entitlement)
        request = canonical_json(request_json)
        reservation = self.store.reserve_usage(firebase_uid=firebase_uid,
            request_id=request_id, payload_digest=hashlib.sha256(request.encode()).hexdigest(),
            entitlement=entitlement, policy=self.policy, now_utc=self._now())
        if reservation.state == 'completed':
            assert reservation.response_json is not None
            return reservation.response_json
        if reservation.state != 'reserved':
            raise BillingError('operation_uncertain')
        submitted = self.store.submit_usage(reservation, policy=self.policy, now_utc=self._now())
        try:
            result = canonical_json(generate())
        except Exception:
            self.store.finish_usage(submitted, response_json=None, now_utc=self._now())
            raise BillingError('operation_uncertain') from None
        completed = self.store.finish_usage(submitted, response_json=result, now_utc=self._now())
        assert completed.response_json is not None
        return completed.response_json

    def _now(self) -> datetime:
        return require_utc(self._now_utc())


def require_utc(value: datetime) -> datetime:
    if not isinstance(value, datetime) or value.tzinfo is None or value.utcoffset() != timedelta(0):
        raise BillingError('invalid_timestamp')
    return value.astimezone(UTC)


def require_code(value: str) -> str:
    if not isinstance(value, str) or re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._:-]{0,127}', value) is None:
        raise BillingError('invalid_request')
    return value


def require_uid(value: str) -> str:
    if not isinstance(value, str) or not 1 <= len(value) <= 128 or '/' in value or any(ord(char) < 32 for char in value):
        raise BillingError('invalid_request')
    return value


def require_purchase_token(value: str) -> None:
    if not isinstance(value, str) or not 1 <= len(value) <= 4096 or any(not 33 <= ord(char) <= 126 for char in value):
        raise BillingError('invalid_request')


def canonical_json(value: str) -> str:
    if not isinstance(value, str) or len(value.encode('utf-8')) > 65536:
        raise BillingError('invalid_request')
    try:
        parsed = json.loads(value, parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
        return json.dumps(parsed, sort_keys=True, ensure_ascii=False, separators=(',', ':'), allow_nan=False)
    except (ValueError, TypeError, RecursionError):
        raise BillingError('invalid_request') from None


def build_billing_service(settings, *, play=None, store=None) -> BillingService | None:
    if not settings.billing_enabled:
        return None
    from lexiquest_ai.play_billing import GooglePlayBilling, GooglePlayTransport
    from lexiquest_ai.firestore_billing import FirestoreBillingStore
    return BillingService(policy=settings.billing_policy(),
        play=play if play is not None else GooglePlayBilling(GooglePlayTransport.production()),
        store=store if store is not None else FirestoreBillingStore.production(),
        account_binding_key=settings.billing_account_binding_key.get_secret_value().encode(),
        now_utc=lambda: datetime.now(UTC))
