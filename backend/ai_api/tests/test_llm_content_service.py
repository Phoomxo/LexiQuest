"""Real stdlib transport regressions with synthetic, network-free responses."""

from __future__ import annotations

import io
from email.message import Message
from urllib.error import HTTPError
from urllib.response import addinfourl

import pytest

from lexiquest_ai.config import Settings
from lexiquest_ai.models import ContentRequest
from lexiquest_ai.services.llm_content_service import LlmContentService, _urllib_client
from lexiquest_ai.services.rate_limiter import ProviderRateLimited


@pytest.mark.parametrize("response_kind", ["http_error", "response"])
@pytest.mark.parametrize("retry_after, expected", [("3600", 3600), (None, 5), ("invalid", 5)])
def test_urllib_retry_after_reaches_service_backoff(
    monkeypatch: pytest.MonkeyPatch,
    response_kind: str,
    retry_after: str | None,
    expected: int,
) -> None:
    headers = Message()
    if retry_after is not None:
        headers["rEtRy-AfTeR"] = retry_after
    body = io.BytesIO(b'{"error":"synthetic rate limit"}')
    calls: list[str] = []

    def fake_urlopen(request, *, timeout):
        calls.append(request.full_url)
        if response_kind == "http_error":
            raise HTTPError(request.full_url, 429, "synthetic", headers, body)
        return addinfourl(body, headers, request.full_url, code=429)

    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen)
    settings = Settings(
        _env_file=None,
        llm_base_url="https://provider.example/v1/",
        llm_model="synthetic-model",
        llm_api_key="synthetic-key",
        fallback_llm_model="",
        gemini_keys="",
        provider_rpm_limit=60,
    )
    try:
        # Deliberately use the default real urllib client and real limiter.
        service = LlmContentService(settings=settings)
        with pytest.raises(ProviderRateLimited) as exc_info:
            service.generate(ContentRequest(text="cat", kind="sentence"))
        assert exc_info.value.retry_after_seconds == expected
        assert calls == ["https://provider.example/v1/chat/completions"]
    finally:
        body.close()


def test_urllib_success_snapshots_headers_before_response_closes(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    headers = Message()
    headers["rEtRy-AfTeR"] = "3600"
    body = io.BytesIO(b'{"choices":[{"message":{"content":"A cat sleeps."}}]}')

    def fake_urlopen(request, *, timeout):
        return addinfourl(body, headers, request.full_url, code=200)

    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen)
    try:
        response = _urllib_client().request(
            "https://provider.example/v1/chat/completions",
            data=b"{}",
            headers={"Content-Type": "application/json"},
            timeout=1,
        )
        assert body.closed
        assert response.status == 200
        assert b"A cat sleeps." in response.body
        # Mutating the original header object must not change the snapshot.
        headers.replace_header("rEtRy-AfTeR", "5")
        assert response.headers["retry-after"] == "3600"
    finally:
        body.close()
