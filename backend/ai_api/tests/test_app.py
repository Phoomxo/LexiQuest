"""Tests for the FastAPI application factory and content endpoint."""

from __future__ import annotations

import logging
import json
import asyncio

import pytest
from fastapi.testclient import TestClient

from lexiquest_ai.app import RequestBodyLimitMiddleware, create_app
from lexiquest_ai.config import Settings
from lexiquest_ai.auth import AuthenticatedUser
from research_support import Harness as ResearchFixture

from conftest import (
    FailingContentService,
    FakeContentService,
    FakeTokenVerifier,
    ProviderErrorContentService,
    UnavailableContentService,
    UnauthorizedContentService,
    UnavailableProviderContentService,
)

_CONTENT_BODY = {
    "kind": "sentence",
    "cefr": "a1",
    "language": "en",
}


def test_billing_is_explicitly_disabled_without_affecting_free_content():
    from test_billing import service_fixture
    service, play, documents, _ = service_fixture()
    content = FakeContentService()
    client = TestClient(create_app(
        content_service=content,
        token_verifier=FakeTokenVerifier(),
        settings=Settings(billing_enabled=False, billing_managed_content_required=False),
        billing_service=service,
    ))
    body = {'text': 'synthetic', **_CONTENT_BODY}
    unauthenticated = client.post('/v1/content', json=body)
    assert unauthenticated.status_code == 401
    assert unauthenticated.json()['detail']['code'] == 'UNAUTHENTICATED'
    assert content.calls == []
    assert documents.values == {}
    response = client.get('/v1/billing/catalog', headers={'Authorization': 'Bearer valid-token'})
    assert response.status_code == 503
    assert response.json()['detail']['code'] == 'BILLING_DISABLED'
    free = client.post('/v1/content', json=body,
        headers={'Authorization': 'Bearer valid-token'})
    assert free.status_code == 200
    assert len(content.calls) == 1
    assert documents.values == {}
    assert play.verifications == []
    assert play.acknowledgements == []


def billing_client(*, anonymous=False, compose_service=True, notification_verifier=None, managed_required=True):
    from test_billing import service_fixture
    service, play, documents, clock = service_fixture()
    verifier = FakeTokenVerifier()
    verifier.verify = lambda token: AuthenticatedUser('synthetic-a', is_anonymous=anonymous)
    settings = Settings(billing_enabled=True, billing_managed_content_required=managed_required,
        billing_policy_revision=service.policy.revision,
        billing_account_binding_key='synthetic-only-account-key-00000000',
        billing_products_json=json.dumps([{'productId': product.product_id,
            'basePlanId': product.base_plan_id, 'entitlements': sorted(product.entitlements),
            'dailyManagedUnits': product.daily_managed_units} for product in service.policy.products]))
    content = FakeContentService()
    client = TestClient(create_app(content_service=content, token_verifier=verifier,
        settings=settings, billing_service=service if compose_service else None,
        billing_notification_verifier=notification_verifier))
    return client, service, play, documents, content


def test_billing_catalog_v2_exposes_managed_quota_before_purchase():
    client, _, _, _, _ = billing_client()
    response = client.get('/v1/billing/catalog', headers={'Authorization': 'Bearer valid-token'})
    assert response.status_code == 200
    assert response.json()['schemaVersion'] == 2
    assert response.json()['managedContentRequired'] is True
    assert response.json()['products'] == [{
        'productId': 'synthetic-premium', 'basePlanId': 'synthetic-monthly',
        'entitlements': ['managedContent'], 'dailyManagedUnits': 2,
    }]


def test_billing_catalog_does_not_claim_enforcement_when_provider_gate_is_disabled():
    client, _, _, _, _ = billing_client(managed_required=False)
    response = client.get('/v1/billing/catalog', headers={'Authorization': 'Bearer valid-token'})
    assert response.status_code == 200
    assert response.json()['managedContentRequired'] is False


def test_billing_verification_budget_stops_before_refresh_and_play_even_with_reused_request_ids():
    from lexiquest_ai.billing import BillingError
    client, service, play, documents, _ = billing_client()
    refreshes = []
    begin_refresh = service.store.begin_refresh
    def begin(**arguments):
        refreshes.append(arguments)
        return begin_refresh(**arguments)
    service.store.begin_refresh = begin
    def denied(**arguments):
        play.verifications.append(arguments)
        raise BillingError('purchase_denied')
    play.verify = denied
    responses = [client.post('/v1/billing/play/verify',
        headers={'Authorization': 'Bearer valid-token'},
        json={'purchaseToken': f'synthetic-invalid-token-{index}',
              'requestId': f'synthetic-request-{index % 2}'}) for index in range(40)]

    assert [response.status_code for response in responses[:20]] == [403] * 20
    assert [response.status_code for response in responses[20:]] == [429] * 20
    assert responses[-1].json()['detail']['code'] == 'BILLING_VERIFICATION_RATE_LIMITED'
    assert responses[-1].headers['Retry-After'] == '60'
    assert len(play.verifications) == len(refreshes) == 20
    assert not any(path.startswith('billing_purchases/') for path in documents.values)
    assert not any(path.startswith('billing_accounts/') for path in documents.values)


def test_billing_catalog_verify_and_entitlement_read_have_no_owner_or_token_fields():
    client, service, _, _, _ = billing_client()
    headers = {'Authorization': 'Bearer valid-token'}
    catalog = client.get('/v1/billing/catalog', headers=headers)
    assert catalog.status_code == 200
    assert catalog.json()['accountIdentifier'] == service.account_identifier('synthetic-a')
    verified = client.post('/v1/billing/play/verify', headers=headers,
        json={'purchaseToken': 'synthetic-token-secret', 'requestId': 'synthetic-verify'})
    assert verified.status_code == 200
    assert verified.json()['grants'][0]['entitlement'] == 'managedContent'
    assert client.get('/v1/billing/entitlements', headers=headers).json() == verified.json()
    for response in (catalog, verified):
        assert 'synthetic-token-secret' not in response.text
        assert 'synthetic-a' not in response.text
        assert 'firebaseUid' not in response.text


@pytest.mark.parametrize('anonymous', [True, None])
def test_billing_requires_a_known_registered_identity(anonymous):
    client, _, _, documents, content = billing_client(anonymous=anonymous)
    headers = {'Authorization': 'Bearer valid-token', 'Idempotency-Key': 'synthetic-1'}
    for method, path, body in [
        ('get', '/v1/billing/catalog', None),
        ('post', '/v1/billing/play/verify', {'purchaseToken': 'synthetic-token-secret', 'requestId': 'synthetic-verify'}),
        ('post', '/v1/content', {'text': 'synthetic', **_CONTENT_BODY}),
    ]:
        response = getattr(client, method)(path, headers=headers, **({'json': body} if body else {}))
        assert response.status_code == 403
        assert response.json()['detail']['code'] == 'BILLING_ACCOUNT_REQUIRED'
    assert documents.values == {}
    assert content.calls == []


def test_paid_content_verifies_quota_before_provider_and_replays_identical_response():
    client, service, _, _, content = billing_client()
    headers = {'Authorization': 'Bearer valid-token', 'Idempotency-Key': 'synthetic-1'}
    body = {'text': 'synthetic', **_CONTENT_BODY}
    denied = client.post('/v1/content', headers=headers, json=body)
    assert denied.status_code == 402
    assert content.calls == []
    service.verify_purchase(firebase_uid='synthetic-a', purchase_token='synthetic-token-secret')
    first = client.post('/v1/content', headers=headers, json=body)
    assert first.status_code == 200
    assert client.post('/v1/content', headers=headers, json=body).json() == first.json()
    assert len(content.calls) == 1
    conflict = client.post('/v1/content', headers=headers, json={**body, 'text': 'different'})
    assert conflict.status_code == 409
    assert len(content.calls) == 1


def test_paid_content_without_idempotency_or_backend_fails_closed():
    client, _, _, _, content = billing_client()
    missing = client.post('/v1/content', headers={'Authorization': 'Bearer valid-token'},
        json={'text': 'synthetic', **_CONTENT_BODY})
    assert missing.status_code == 400
    assert content.calls == []
    unavailable, _, _, _, content = billing_client(compose_service=False)
    assert unavailable.get('/health/ready').status_code == 503
    assert unavailable.get('/v1/billing/catalog', headers={'Authorization': 'Bearer valid-token'}).status_code == 503
    assert content.calls == []


def test_invalid_purchase_body_never_echoes_its_token():
    client, _, _, documents, _ = billing_client()
    secret = 'synthetic-token-secret-' * 220
    response = client.post('/v1/billing/play/verify', headers={'Authorization': 'Bearer valid-token'},
        json={'purchaseToken': secret, 'requestId': 'synthetic-verify', 'firebaseUid': 'attacker-selected-owner'})
    assert response.status_code == 422
    assert response.json()['detail']['code'] == 'BILLING_INVALID_REQUEST'
    assert secret not in response.text
    assert 'attacker-selected-owner' not in response.text
    assert documents.values == {}


def test_billing_notifications_stay_unavailable_without_configured_push_identity():
    client, _, _, documents, _ = billing_client()
    response = client.post('/v1/billing/play/notifications', json={'message': {'data': 'e30='}},
        headers={'Authorization': 'Bearer valid-token'})
    assert response.status_code == 503
    assert response.json()['detail']['code'] == 'BILLING_NOTIFICATION_UNAVAILABLE'
    assert documents.values == {}


def test_billing_notification_rejects_user_token_then_refreshes_actual_purchase():
    from test_play_billing import AUDIENCE, EMAIL, notification, push_claims
    from lexiquest_ai.play_billing import GooglePubSubPushVerifier
    from lexiquest_ai.billing import VerifiedPlayPurchase
    from test_billing import NOW
    def decode(token, audience):
        if token != 'synthetic-pubsub-signed-token':
            raise ValueError('synthetic-invalid-push-token')
        return push_claims()
    verifier = GooglePubSubPushVerifier(audience=AUDIENCE, service_account_email=EMAIL, decode=decode)
    client, service, play, documents, content = billing_client(notification_verifier=verifier)
    service.verify_purchase(firebase_uid='synthetic-a', purchase_token='synthetic-token-secret')
    payload = notification({'packageName': service.policy.package_name,
        'subscriptionNotification': {'notificationType': 2, 'purchaseToken': 'synthetic-token-secret'}})
    before = repr(documents.values)
    denied = client.post('/v1/billing/play/notifications', json=payload,
        headers={'Authorization': 'Bearer valid-token'})
    assert denied.status_code == 401
    assert repr(documents.values) == before
    play.result = VerifiedPlayPurchase('synthetic-premium', 'synthetic-monthly',
        service.account_identifier('synthetic-a'), 'SUBSCRIPTION_STATE_EXPIRED', NOW, NOW, True)
    accepted = client.post('/v1/billing/play/notifications', json=payload,
        headers={'Authorization': 'Bearer synthetic-pubsub-signed-token'})
    assert accepted.status_code == 200
    assert accepted.json() == {'accepted': True, 'knownPurchase': True}
    assert service.entitlements(firebase_uid='synthetic-a').grants == ()
    assert content.calls == []


@pytest.mark.parametrize("length", [None, "1"])
def test_content_limits_actual_chunked_body_bytes(client: TestClient, length) -> None:
    headers = {"Content-Type": "application/json", "Authorization": "Bearer valid-token"}
    if length is not None:
        headers["Content-Length"] = length
    response = client.post(
        "/v1/content", headers=headers,
        content=iter([b" " * 60_000, b" " * 60_000,
                      json.dumps({"text": "Cat", **_CONTENT_BODY}).encode()]),
    )
    assert response.status_code == 413
    assert response.json()["detail"]["code"] == "PAYLOAD_TOO_LARGE"


@pytest.mark.parametrize("length", ["junk", "-1", "1.5"])
def test_content_rejects_invalid_content_length(client: TestClient, length: str) -> None:
    response = client.post("/v1/content", content=b"{}", headers={"Content-Length": length})
    assert response.status_code == 400


def test_content_accepts_body_at_byte_limit(client: TestClient) -> None:
    body = json.dumps({"text": "Cat", **_CONTENT_BODY}).encode()
    response = client.post(
        "/v1/content", headers={"Content-Type": "application/json", "Authorization": "Bearer valid-token"},
        content=iter([b" " * (100_000 - len(body)), body]),
    )
    assert response.status_code == 200


def test_body_limit_stops_receiving_before_auth_or_json_parsing() -> None:
    received = 0
    responses = []

    async def downstream(scope, receive, send):
        pytest.fail("An oversized request must not reach the application.")

    async def receive():
        nonlocal received
        received += 1
        assert received <= 2
        return {"type": "http.request", "body": b" " * 60_000, "more_body": True}

    async def send(message):
        responses.append(message)

    middleware = RequestBodyLimitMiddleware(downstream)
    asyncio.run(middleware({"type": "http", "method": "POST", "headers": []}, receive, send))
    assert received == 2
    assert responses[0]["status"] == 413


def test_health_endpoints(client: TestClient) -> None:
    assert client.get("/health/live").json() == {"status": "live"}
    assert client.get("/health/ready").json() == {"status": "ready"}


def test_ready_fails_closed_when_research_is_enabled_without_service(
    token_verifier: FakeTokenVerifier,
) -> None:
    research = ResearchFixture()
    client = TestClient(create_app(
        content_service=FakeContentService(),
        token_verifier=token_verifier,
        settings=research.settings(),
    ))

    response = client.get("/health/ready")

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "RESEARCH_AUTHORITY_UNAVAILABLE"
    assert client.get("/health/live").status_code == 200
    ordinary = client.post("/v1/content", json={"text": "synthetic", **_CONTENT_BODY},
                           headers={"Authorization": "Bearer valid-token"})
    assert ordinary.status_code == 200
    assert research.documents.writes == 0


@pytest.mark.parametrize("research_enabled", [False, True])
def test_ready_accepts_disabled_or_composed_research_without_collecting_data(
    token_verifier: FakeTokenVerifier,
    research_enabled: bool,
) -> None:
    research = ResearchFixture()
    content = FakeContentService()
    client = TestClient(create_app(
        content_service=content,
        token_verifier=token_verifier,
        settings=research.settings() if research_enabled else Settings(_env_file=None),
        research_service=research.service if research_enabled else None,
    ))

    response = client.get("/health/ready")

    assert response.status_code == 200
    assert response.json() == {"status": "ready"}
    assert research.documents.writes == 0
    assert content.calls == []


def test_ready_reports_provider_failure_before_missing_research_service(
    token_verifier: FakeTokenVerifier,
) -> None:
    client = TestClient(create_app(
        content_service=UnavailableContentService(),
        token_verifier=token_verifier,
        settings=ResearchFixture().settings(),
    ))

    response = client.get("/health/ready")

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "PROVIDER_UNAVAILABLE"


def test_content_rejects_missing_token(client: TestClient) -> None:
    response = client.post("/v1/content", json={"text": "Cat", **_CONTENT_BODY})

    assert response.status_code == 401
    assert response.json()["detail"]["code"] == "UNAUTHENTICATED"


def test_content_returns_generated_text(client: TestClient) -> None:
    response = client.post(
        "/v1/content",
        headers={"Authorization": "Bearer valid-token"},
        json={"text": "Cat", **_CONTENT_BODY},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["text"] == "The cat sleeps peacefully."
    assert body["kind"] == "sentence"
    assert body["language"] == "en"
    assert body["cefr"] == "a1"
    assert body["model_version"] == "test"
    assert body["cached"] is False


def test_ready_returns_503_when_service_not_configured(
    token_verifier: FakeTokenVerifier,
) -> None:
    app = create_app(
        content_service=UnavailableContentService(),
        token_verifier=token_verifier,
        settings=Settings(),
    )
    response = TestClient(app).get("/health/ready")

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "PROVIDER_UNAVAILABLE"


def test_ready_fails_closed_when_account_deletion_is_enabled_without_service(
    token_verifier: FakeTokenVerifier,
) -> None:
    app = create_app(
        content_service=FakeContentService(),
        token_verifier=token_verifier,
        settings=Settings(account_deletion_enabled=True),
        account_deletion_service=None,
    )

    response = TestClient(app).get("/health/ready")

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "ACCOUNT_DELETION_UNAVAILABLE"


@pytest.mark.parametrize("probe_ready", [False, True])
def test_ready_requires_runtime_account_deletion_attestation(
    token_verifier: FakeTokenVerifier,
    probe_ready: bool,
) -> None:
    class _Probe:
        def is_ready(self) -> bool:
            return probe_ready

    app = create_app(
        content_service=FakeContentService(),
        token_verifier=token_verifier,
        settings=Settings(account_deletion_enabled=True),
        account_deletion_service=object(),  # type: ignore[arg-type]
        account_deletion_readiness_probe=_Probe(),
    )

    response = TestClient(app).get("/health/ready")

    assert response.status_code == (200 if probe_ready else 503)


def test_ready_fails_closed_when_account_deletion_probe_is_missing(
    token_verifier: FakeTokenVerifier,
) -> None:
    app = create_app(
        content_service=FakeContentService(),
        token_verifier=token_verifier,
        settings=Settings(account_deletion_enabled=True),
        account_deletion_service=object(),  # type: ignore[arg-type]
    )

    response = TestClient(app).get("/health/ready")

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "ACCOUNT_DELETION_UNAVAILABLE"


def test_content_enforces_configured_text_length(
    token_verifier: FakeTokenVerifier,
    make_client,
) -> None:
    settings = Settings(max_text_length=10)
    client = make_client(
        content_service=FakeContentService(), settings=settings
    )

    response = client.post(
        "/v1/content",
        headers={"Authorization": "Bearer valid-token"},
        json={"text": "x" * 11, **_CONTENT_BODY},
    )

    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "TEXT_TOO_LONG"


def test_content_failure_hides_secret_detail_and_correlates_request_id(
    token_verifier: FakeTokenVerifier,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """A generation failure returns a safe 503 correlated by ``request_id`` and
    never leaks the secret request text or the internal exception message."""

    secret_text = "TOPSECRET-payload-7c9f3a"
    app = create_app(
        content_service=FailingContentService(),
        token_verifier=token_verifier,
        settings=Settings(),
    )

    with caplog.at_level(logging.ERROR):
        response = TestClient(app).post(
            "/v1/content",
            headers={"Authorization": "Bearer valid-token"},
            json={"text": secret_text, **_CONTENT_BODY},
        )

    assert response.status_code == 503
    detail = response.json()["detail"]
    assert detail["code"] == "CONTENT_GENERATION_FAILED"
    assert detail["message"] == "Content generation could not be completed."
    assert response.headers["Retry-After"] == "5"

    request_id = detail["request_id"]
    assert request_id
    assert request_id == response.headers["X-Request-ID"]
    assert request_id in caplog.text

    captured = f"{response.text}\n{caplog.text}"
    assert secret_text not in captured
    assert FailingContentService.internal_error_message not in captured
    assert "RuntimeError" in caplog.text


def test_content_provider_unauthorized_maps_to_stable_error(
    token_verifier: FakeTokenVerifier,
    make_client,
) -> None:
    client = make_client(content_service=UnauthorizedContentService())

    response = client.post(
        "/v1/content",
        headers={"Authorization": "Bearer valid-token"},
        json={"text": "Cat", **_CONTENT_BODY},
    )

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "PROVIDER_UNAUTHORIZED"


def test_content_provider_unavailable_maps_to_stable_error(
    token_verifier: FakeTokenVerifier,
    make_client,
) -> None:
    client = make_client(content_service=UnavailableProviderContentService())

    response = client.post(
        "/v1/content",
        headers={"Authorization": "Bearer valid-token"},
        json={"text": "Cat", **_CONTENT_BODY},
    )

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "PROVIDER_UNAVAILABLE"


def test_content_provider_error_maps_to_generation_failed(
    token_verifier: FakeTokenVerifier,
    make_client,
) -> None:
    """A generic provider error (malformed response) is also surfaced as the
    stable CONTENT_GENERATION_FAILED, never a raw 500."""

    client = make_client(content_service=ProviderErrorContentService())

    response = client.post(
        "/v1/content",
        headers={"Authorization": "Bearer valid-token"},
        json={"text": "Cat", **_CONTENT_BODY},
    )

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "CONTENT_GENERATION_FAILED"
