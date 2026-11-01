from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
import json
import re
import base64
import binascii
from urllib.parse import quote

from lexiquest_ai.billing import (
    BillingError, BillingPolicy, VerifiedPlayPurchase, require_code,
    require_purchase_token, require_utc,
)


@dataclass(frozen=True, slots=True)
class PlayResponse:
    status: int
    body: bytes


class GooglePlayTransport:
    def __init__(self, credentials) -> None:
        from google.auth.transport.requests import AuthorizedSession
        self._session = AuthorizedSession(credentials)

    @classmethod
    def production(cls) -> GooglePlayTransport:
        import google.auth
        credentials, _ = google.auth.default(scopes=[
            'https://www.googleapis.com/auth/androidpublisher',
        ])
        return cls(credentials)

    def request(self, method: str, url: str, *, body: dict | None = None) -> PlayResponse:
        try:
            response = self._session.request(method, url, json=body, timeout=15)
            if len(response.content) > 262144:
                raise BillingError('billing_unavailable')
            return PlayResponse(response.status_code, response.content)
        except Exception:
            raise BillingError('billing_unavailable') from None

    def close(self) -> None:
        self._session.close()


class GooglePlayBilling:
    def __init__(self, transport):
        self._transport = transport

    def verify(self, *, package_name: str, purchase_token: str,
               policy: BillingPolicy, checked_at_utc: datetime) -> VerifiedPlayPurchase:
        require_code(package_name)
        require_purchase_token(purchase_token)
        require_utc(checked_at_utc)
        if package_name != policy.package_name:
            raise BillingError('purchase_denied')
        response = self._request('GET', f'{self._base(package_name)}/purchases/subscriptionsv2/tokens/{quote(purchase_token, safe="")}')
        if response.status != 200:
            raise BillingError('purchase_denied' if response.status in {400, 404, 410} else 'billing_unavailable')
        try:
            resource = json.loads(response.body, object_pairs_hook=_unique_object)
            state = resource['subscriptionState']
            if state not in {
                'SUBSCRIPTION_STATE_PENDING', 'SUBSCRIPTION_STATE_ACTIVE',
                'SUBSCRIPTION_STATE_PAUSED', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
                'SUBSCRIPTION_STATE_ON_HOLD', 'SUBSCRIPTION_STATE_CANCELED',
                'SUBSCRIPTION_STATE_EXPIRED', 'SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED',
            }:
                raise ValueError()
            acknowledgement = resource['acknowledgementState']
            if acknowledgement not in {'ACKNOWLEDGEMENT_STATE_PENDING', 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED'}:
                raise ValueError()
            account = resource['externalAccountIdentifiers']['obfuscatedExternalAccountId']
            if not isinstance(account, str) or re.fullmatch(r'[0-9a-f]{64}', account) is None:
                raise ValueError()
            items = resource['lineItems']
            if not isinstance(items, list) or not 1 <= len(items) <= 32:
                raise ValueError()
            matches = []
            for item in items:
                product_id = item['productId']
                base_plan_id = item['offerDetails']['basePlanId']
                try:
                    policy.product(product_id, base_plan_id)
                except BillingError:
                    continue
                expiry = _timestamp(item.get('expiryTime')) if item.get('expiryTime') is not None else checked_at_utc
                matches.append((expiry, product_id, base_plan_id))
            if len(matches) != 1:
                raise ValueError()
            expiry, product_id, base_plan_id = matches[0]
            return VerifiedPlayPurchase(product_id, base_plan_id, account, state,
                expiry, checked_at_utc, acknowledgement == 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED')
        except (ValueError, TypeError, KeyError, OverflowError, RecursionError):
            raise BillingError('purchase_denied') from None

    def acknowledge(self, *, package_name: str, product_id: str, purchase_token: str) -> None:
        require_code(package_name)
        require_code(product_id)
        require_purchase_token(purchase_token)
        response = self._request('POST', f'{self._base(package_name)}/purchases/subscriptions/{quote(product_id, safe="")}/tokens/{quote(purchase_token, safe="")}:acknowledge', body={})
        if response.status not in {200, 204}:
            raise BillingError('billing_unavailable')

    def _request(self, method: str, url: str, **kwargs) -> PlayResponse:
        try:
            response = self._transport.request(method, url, **kwargs)
            if type(response.status) is not int or not isinstance(response.body, bytes) or len(response.body) > 262144:
                raise ValueError()
            return response
        except Exception:
            raise BillingError('billing_unavailable') from None

    @staticmethod
    def _base(package_name: str) -> str:
        return f'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{quote(package_name, safe="")}'


def _timestamp(value: object) -> datetime:
    if not isinstance(value, str) or len(value) > 40:
        raise ValueError()
    timestamp = datetime.fromisoformat(value.replace('Z', '+00:00'))
    return require_utc(timestamp).astimezone(UTC)


def _unique_object(items):
    result = {}
    for key, value in items:
        if key in result:
            raise ValueError()
        result[key] = value
    return result


class GooglePubSubPushVerifier:
    def __init__(self, *, audience: str, service_account_email: str, decode=None) -> None:
        if not audience or not service_account_email.endswith('.gserviceaccount.com'):
            raise BillingError('invalid_configuration')
        self._audience = audience
        self._email = service_account_email
        self._decode = decode if decode is not None else self._verify_google_token

    def verify(self, token: str) -> None:
        try:
            claims = self._decode(token, self._audience)
            if (claims.get('aud') != self._audience or claims.get('email') != self._email
                    or claims.get('email_verified') is not True
                    or claims.get('iss') not in {'accounts.google.com', 'https://accounts.google.com'}):
                raise ValueError()
        except Exception:
            raise BillingError('notification_unauthenticated') from None

    @staticmethod
    def _verify_google_token(token: str, audience: str):
        from google.auth.transport.requests import Request
        from google.oauth2.id_token import verify_oauth2_token
        return verify_oauth2_token(token, Request(), audience=audience)


def decode_play_notification(envelope: dict, *, package_name: str) -> str | None:
    try:
        data = envelope['message']['data']
        if not isinstance(data, str) or len(data) > 87384:
            raise ValueError()
        raw = base64.b64decode(data, validate=True)
        if len(raw) > 65536:
            raise ValueError()
        notification = json.loads(raw, object_pairs_hook=_unique_object)
        if notification['packageName'] != package_name:
            raise ValueError()
        if 'testNotification' in notification:
            return None
        candidates = [notification[key] for key in ('subscriptionNotification', 'voidedPurchaseNotification') if key in notification]
        if len(candidates) != 1:
            raise ValueError()
        token = candidates[0]['purchaseToken']
        require_purchase_token(token)
        return token
    except (KeyError, TypeError, ValueError, BillingError, binascii.Error, RecursionError):
        raise BillingError('invalid_request') from None
