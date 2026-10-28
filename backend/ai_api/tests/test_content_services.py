from datetime import timedelta
from types import SimpleNamespace

import pytest

from lexiquest_ai.config import Settings
from lexiquest_ai.models import ContentRequest, ContentResult
from lexiquest_ai.services.cache import CachingContentGenerator, ContentCache
from lexiquest_ai.services.llm_content_service import LlmContentService
from lexiquest_ai.services.rate_limiter import ProviderRateLimited, RateLimitedClient


@pytest.mark.parametrize("first,second", [("Polish", "polish"), ("US", "us")])
def test_cached_content_keeps_case_sensitive_word_meaning(first: str, second: str) -> None:
    class _Generator:
        def generate(self, request):
            return ContentResult(text=request.text, kind=request.kind, model_version="synthetic")

    generator = CachingContentGenerator(inner=_Generator(), cache=ContentCache(
        ttl=timedelta(days=1), max_entries=5))
    generator.generate(ContentRequest(text=first, kind="explanation"), model_version="synthetic")
    actual = generator.generate(ContentRequest(text=second, kind="explanation"), model_version="synthetic")
    assert actual.text == second
    assert actual.cached is False
    assert generator.generate(ContentRequest(text=second, kind="explanation"),
                              model_version="synthetic").cached is True


def test_fallback_credential_has_its_own_rate_budget_without_bypassing_limits() -> None:
    class _Client:
        def __init__(self):
            self.keys = []

        def request(self, url, *, data, headers, timeout):
            key = headers["Authorization"]
            self.keys.append(key)
            if key == "Bearer synthetic-primary":
                return SimpleNamespace(status=429, body=b"{}")
            return SimpleNamespace(status=200, body=b'{"choices":[{"message":{"content":"synthetic success"}}]}')

    client = _Client()
    service = LlmContentService(settings=Settings(
        llm_base_url="https://synthetic.invalid/v1/", llm_api_key="synthetic-primary",
        fallback_llm_base_url="https://synthetic.invalid/v1/",
        fallback_llm_api_key="synthetic-fallback", provider_rpm_limit=1), http_client=client)
    request = ContentRequest(text="station", kind="sentence")
    assert service.generate(request).text == "synthetic success"
    assert client.keys == ["Bearer synthetic-primary", "Bearer synthetic-fallback"]
    with pytest.raises(ProviderRateLimited):
        service.generate(request)
    assert len(client.keys) == 2
    assert "synthetic-primary" not in repr(service._get_client()._limiters)
    assert "synthetic-fallback" not in repr(service._get_client()._limiters)


def test_same_credential_keeps_one_budget_on_the_same_url() -> None:
    client = RateLimitedClient(inner=SimpleNamespace(request=lambda *a, **kw: None), max_per_minute=1)
    client.request("https://synthetic.invalid", data=b"", headers={"Authorization": "Bearer synthetic"}, timeout=1)
    with pytest.raises(ProviderRateLimited):
        client.request("https://synthetic.invalid", data=b"", headers={"authorization": "Bearer synthetic"}, timeout=1)
