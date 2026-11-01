import json
from datetime import UTC, datetime, timedelta
import pytest

from lexiquest_ai.billing import BillingError, BillingPolicy, BillingProduct
from lexiquest_ai.play_billing import GooglePlayBilling, PlayResponse
from lexiquest_ai.play_billing import GooglePubSubPushVerifier, decode_play_notification
import base64


NOW = datetime(2026, 11, 1, tzinfo=UTC)
POLICY = BillingPolicy('com.lexiquest.app', 'synthetic-v1', (
    BillingProduct('synthetic-premium', 'synthetic-monthly', frozenset({'managedContent'}), 2),
))


class Transport:
    def __init__(self, payload):
        self.payload = payload
        self.calls = []

    def request(self, method, url, **kwargs):
        self.calls.append((method, url, kwargs))
        return PlayResponse(200, json.dumps(self.payload).encode())


def resource(state='SUBSCRIPTION_STATE_CANCELED'):
    return {
        'subscriptionState': state,
        'acknowledgementState': 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
        'externalAccountIdentifiers': {'obfuscatedExternalAccountId': 'a' * 64},
        'lineItems': [{'productId': 'synthetic-premium',
                       'expiryTime': (NOW + timedelta(days=2)).isoformat(),
                       'offerDetails': {'basePlanId': 'synthetic-monthly'}}],
    }


def test_cancelled_subscription_keeps_verified_paid_access_until_expiry():
    transport = Transport(resource())
    result = GooglePlayBilling(transport).verify(package_name=POLICY.package_name,
        purchase_token='synthetic/token?', policy=POLICY, checked_at_utc=NOW)

    assert result.permits_access
    assert result.expires_at_utc == NOW + timedelta(days=2)
    assert transport.calls[0][0] == 'GET'
    assert transport.calls[0][1].endswith('/tokens/synthetic%2Ftoken%3F')


@pytest.mark.parametrize('state', ['SUBSCRIPTION_STATE_PENDING', 'SUBSCRIPTION_STATE_ON_HOLD',
    'SUBSCRIPTION_STATE_EXPIRED', 'SUBSCRIPTION_STATE_PAUSED'])
def test_authoritative_non_entitled_states_are_not_grants(state):
    result = GooglePlayBilling(Transport(resource(state))).verify(package_name=POLICY.package_name,
        purchase_token='synthetic-token', policy=POLICY, checked_at_utc=NOW)
    assert not result.permits_access


@pytest.mark.parametrize('mutation', [
    lambda item: item.update(subscriptionState='SUBSCRIPTION_STATE_UNKNOWN_FUTURE'),
    lambda item: item.update(acknowledgementState='unknown'),
    lambda item: item.update(externalAccountIdentifiers={}),
    lambda item: item['lineItems'][0].update(productId='unconfigured'),
    lambda item: item['lineItems'][0]['offerDetails'].update(basePlanId='unconfigured'),
    lambda item: item['lineItems'][0].update(expiryTime='not-a-date'),
    lambda item: item['lineItems'].append(dict(item['lineItems'][0])),
])
def test_malformed_unknown_or_ambiguous_purchase_is_rejected(mutation):
    payload = resource()
    mutation(payload)
    with pytest.raises(BillingError, match='purchase_denied'):
        GooglePlayBilling(Transport(payload)).verify(package_name=POLICY.package_name,
            purchase_token='synthetic-token', policy=POLICY, checked_at_utc=NOW)


def test_acknowledgement_uses_fixed_package_product_and_encoded_token():
    transport = Transport({})
    GooglePlayBilling(transport).acknowledge(package_name=POLICY.package_name,
        product_id='synthetic-premium', purchase_token='synthetic/token?')
    method, url, kwargs = transport.calls[0]
    assert method == 'POST'
    assert url.endswith('/purchases/subscriptions/synthetic-premium/tokens/synthetic%2Ftoken%3F:acknowledge')
    assert kwargs == {'body': {}}


def test_transport_exception_does_not_expose_token_or_credential():
    class Unavailable:
        def request(self, method, url):
            raise RuntimeError(url + ' synthetic-credential')
    with pytest.raises(BillingError) as caught:
        GooglePlayBilling(Unavailable()).verify(package_name=POLICY.package_name,
            purchase_token='synthetic-token-secret', policy=POLICY, checked_at_utc=NOW)
    assert str(caught.value) == 'billing_unavailable'
    assert caught.value.__cause__ is None


AUDIENCE = 'https://synthetic.example.test/v1/billing/play/notifications'
EMAIL = 'synthetic-push@synthetic-project.iam.gserviceaccount.com'


def push_claims():
    return {'aud': AUDIENCE, 'email': EMAIL, 'email_verified': True, 'iss': 'https://accounts.google.com'}


@pytest.mark.parametrize('mutation', [
    lambda claims: claims.update(aud='https://wrong.example.test'),
    lambda claims: claims.update(email='other@synthetic-project.iam.gserviceaccount.com'),
    lambda claims: claims.update(email_verified=False),
    lambda claims: claims.update(email_verified='true'),
    lambda claims: claims.update(iss='https://untrusted.example.test'),
])
def test_push_identity_rejects_wrong_audience_account_verification_or_issuer(mutation):
    claims = push_claims()
    mutation(claims)
    verifier = GooglePubSubPushVerifier(audience=AUDIENCE, service_account_email=EMAIL,
        decode=lambda token, audience: claims)
    with pytest.raises(BillingError, match='notification_unauthenticated'):
        verifier.verify('synthetic-signed-token')


def test_push_identity_uses_signature_decoder_and_exact_configured_audience():
    calls = []
    def decode(token, audience):
        calls.append((token, audience))
        return push_claims()
    GooglePubSubPushVerifier(audience=AUDIENCE, service_account_email=EMAIL,
        decode=decode).verify('synthetic-signed-token')
    assert calls == [('synthetic-signed-token', AUDIENCE)]


def notification(payload):
    return {'message': {'data': base64.b64encode(json.dumps(payload).encode()).decode()}}


def test_notification_is_only_a_hint_and_has_no_entitlement_from_its_event_type():
    envelope = notification({'packageName': POLICY.package_name,
        'subscriptionNotification': {'notificationType': 'invented-grant', 'purchaseToken': 'synthetic-token'}})
    assert decode_play_notification(envelope, package_name=POLICY.package_name) == 'synthetic-token'
    assert decode_play_notification(notification({'packageName': POLICY.package_name, 'testNotification': {}}),
        package_name=POLICY.package_name) is None


@pytest.mark.parametrize('envelope', [
    {}, {'message': {'data': '!not-base64'}},
    notification({'packageName': 'other.package', 'subscriptionNotification': {'purchaseToken': 'synthetic-token'}}),
    notification({'packageName': POLICY.package_name, 'subscriptionNotification': {}}),
    notification({'packageName': POLICY.package_name, 'subscriptionNotification': {'purchaseToken': 'synthetic-token'},
        'voidedPurchaseNotification': {'purchaseToken': 'synthetic-token'}}),
])
def test_notification_boundary_rejects_malformed_or_wrong_package(envelope):
    with pytest.raises(BillingError, match='invalid_request'):
        decode_play_notification(envelope, package_name=POLICY.package_name)
