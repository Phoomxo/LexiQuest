from datetime import timedelta
from email.message import Message
import http.client
import io
import traceback
from types import SimpleNamespace
import urllib.error
import urllib.request
from urllib.response import addinfourl

import pytest

from lexiquest_ai.config import Settings
from lexiquest_ai.models import ContentRequest, ContentResult
from lexiquest_ai.services.cache import CachingContentGenerator, ContentCache
from lexiquest_ai.services.llm_content_service import (
    LlmContentService,
    ProviderError,
    ProviderUnauthorized,
    ProviderUnavailable,
    _ProviderEndpoint,
    _urllib_client,
)
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


@pytest.fixture
def urllib_transport(monkeypatch):
    original_build = urllib.request.build_opener

    class Body(io.BytesIO):
        def __init__(self, contents):
            super().__init__(contents)
            self.read_sizes = []
            self.read_error = None

        def read(self, size=-1):
            self.read_sizes.append(size)
            if self.read_error is not None:
                raise self.read_error
            return super().read(size)

    class Transport(urllib.request.BaseHandler):
        handler_order = 100

        def __init__(self, responses):
            self.responses = responses
            self.requests = []
            self.bodies = []
            self.read_error = None

        def http_open(self, request):
            index = len(self.requests)
            self.requests.append(request)
            status, headers, contents = self.responses[index]
            body = Body(contents)
            body.read_error = self.read_error
            self.bodies.append(body)
            message = Message()
            for name, value in headers.items():
                message[name] = value
            response = addinfourl(body, message, request.full_url, status)
            response.msg = "synthetic response"
            return response

        https_open = http_open

    def install(responses):
        transport = Transport(responses)

        def build(*handlers):
            return original_build(urllib.request.ProxyHandler({}), transport, *handlers)

        monkeypatch.setattr(urllib.request, "build_opener", build)
        monkeypatch.setattr(urllib.request, "urlopen", build().open)
        return transport

    return install


def provider_settings(**changes):
    return Settings(**{"llm_base_url": "https://provider.synthetic.invalid/v1/",
                       "llm_api_key": "synthetic-provider-key", "fallback_llm_model": "", **changes})


@pytest.mark.parametrize("status", [301, 302, 303, 307, 308])
@pytest.mark.parametrize("target", ["https://other.synthetic.invalid/collect", "http://other.synthetic.invalid/collect"])
def test_provider_redirect_never_forwards_authorization(urllib_transport, status, target):
    transport = urllib_transport([
        (status, {"Location": target}, b"synthetic redirect"),
        (200, {}, b'{"choices":[{"message":{"content":"unexpected redirected success"}}]}'),
    ])
    service = LlmContentService(settings=provider_settings())
    with pytest.raises(ProviderError, match="unexpected provider status") as error:
        service.generate(ContentRequest(text="station", kind="sentence"))
    assert len(transport.requests) == 1
    assert transport.requests[0].get_header("Authorization") == "Bearer synthetic-provider-key"
    assert all(body.closed for body in transport.bodies)
    assert "synthetic-provider-key" not in str(error.value)
    assert target not in str(error.value)


@pytest.mark.parametrize("status", [301, 302, 303, 307, 308])
def test_malformed_redirect_is_rejected_without_parsing_location(urllib_transport, status):
    transport = urllib_transport([(status, {
        "Location": "https://[synthetic-provider-key]/collect",
    }, b"synthetic redirect")])
    with pytest.raises(ProviderError, match="unexpected provider status"):
        LlmContentService(settings=provider_settings()).generate(
            ContentRequest(text="station", kind="sentence"))
    assert len(transport.requests) == 1
    assert all(body.closed for body in transport.bodies)


@pytest.mark.parametrize("status", [200, 429])
@pytest.mark.parametrize("missing_bytes", [0, 5])
def test_real_http_response_framing_is_checked_before_acceptance(monkeypatch, status, missing_bytes):
    payload = b'{"choices":[{"message":{"content":"synthetic"}}]}'
    stream = io.BytesIO((f"HTTP/1.1 {status} Synthetic\r\n"
                         f"Content-Length: {len(payload) + missing_bytes}\r\n\r\n").encode() + payload)
    response = http.client.HTTPResponse(SimpleNamespace(makefile=lambda *args: stream))
    response.begin()

    def open_response(request, *, timeout):
        if status >= 400:
            raise urllib.error.HTTPError(request.full_url, status, "synthetic", response.headers, response)
        return response

    monkeypatch.setattr(urllib.request, "build_opener", lambda *handlers: SimpleNamespace(open=open_response))
    client = _urllib_client()
    if missing_bytes:
        with pytest.raises(ProviderUnavailable, match="transport error"):
            client.request("https://provider.synthetic.invalid/v1/chat/completions", data=b"{}", headers={}, timeout=1)
    else:
        actual = client.request("https://provider.synthetic.invalid/v1/chat/completions", data=b"{}", headers={}, timeout=1)
        assert actual.status == status and actual.body == payload
    assert stream.closed


@pytest.mark.parametrize("status", [200, 401, 403, 429, 500])
def test_provider_response_size_is_bounded_and_stream_closed(urllib_transport, status):
    transport = urllib_transport([(status, {}, b"x" * (1024 * 1024 + 2))])
    with pytest.raises(ProviderError, match="size limit"):
        _urllib_client().request("https://provider.synthetic.invalid/v1/chat/completions",
                                 data=b"{}", headers={}, timeout=1)
    assert transport.bodies[0].read_sizes == [1024 * 1024 + 1]
    assert transport.bodies[0].closed


@pytest.mark.parametrize("status", [200, 429])
def test_provider_response_at_size_boundary_is_not_truncated(urllib_transport, status):
    payload = b"x" * (1024 * 1024)
    transport = urllib_transport([(status, {"Retry-After": "3600", "X-Private": "discard"}, payload)])
    response = _urllib_client().request("https://provider.synthetic.invalid/v1/chat/completions",
                                        data=b"{}", headers={}, timeout=1)
    assert response.status == status
    assert response.body == payload
    assert response.headers == {"Retry-After": "3600"}
    assert transport.bodies[0].closed


@pytest.mark.parametrize("retry_after,expected", [("3600", 3600), ("not-a-number", 5), (None, 5)])
def test_stdlib_provider_rate_limit_keeps_retry_after(urllib_transport, retry_after, expected):
    headers = {} if retry_after is None else {"retry-after": retry_after}
    transport = urllib_transport([(429, headers, b"{}")])
    service = LlmContentService(settings=provider_settings())
    with pytest.raises(ProviderRateLimited) as error:
        service.generate(ContentRequest(text="station", kind="sentence"))
    assert error.value.retry_after_seconds == expected
    assert transport.bodies[0].closed


@pytest.mark.parametrize("status,error_type", [(400, ProviderError), (401, ProviderUnauthorized),
                                               (403, ProviderUnauthorized), (503, ProviderUnavailable)])
def test_stdlib_provider_http_errors_keep_existing_classification(urllib_transport, status, error_type):
    transport = urllib_transport([(status, {}, b"synthetic private provider body")])
    with pytest.raises(error_type) as error:
        LlmContentService(settings=provider_settings()).generate(ContentRequest(text="station", kind="sentence"))
    assert transport.bodies[0].closed
    assert "synthetic private provider body" not in str(error.value)


def test_stdlib_provider_success_keeps_content_and_closes_stream(urllib_transport):
    transport = urllib_transport([(200, {}, b'{"choices":[{"message":{"content":"synthetic success"}}]}')])
    result = LlmContentService(settings=provider_settings()).generate(ContentRequest(text="station", kind="sentence"))
    assert result.text == "synthetic success"
    assert transport.bodies[0].closed


@pytest.mark.parametrize("status", [401, 403, 429, 503])
def test_stdlib_provider_failures_keep_explicit_fallback_credentials(urllib_transport, status):
    transport = urllib_transport([
        (status, {"Retry-After": "3600"}, b"{}"),
        (200, {}, b'{"choices":[{"message":{"content":"synthetic fallback"}}]}'),
    ])
    service = LlmContentService(settings=provider_settings(
        fallback_llm_model="synthetic-fallback",
        fallback_llm_base_url="https://fallback.synthetic.invalid/v1/",
        fallback_llm_api_key="synthetic-fallback-key"))
    result = service.generate(ContentRequest(text="station", kind="sentence"))
    assert result.text == "synthetic fallback"
    assert [request.get_header("Authorization") for request in transport.requests] == [
        "Bearer synthetic-provider-key", "Bearer synthetic-fallback-key"]
    assert transport.requests[1].full_url.startswith("https://fallback.synthetic.invalid/")
    assert all(body.closed for body in transport.bodies)


@pytest.mark.parametrize("status", [200, 500])
@pytest.mark.parametrize("failure,args", [(OSError, ("synthetic-private-body",)),
                                         (http.client.IncompleteRead, (b"synthetic-private-body", 10))])
def test_provider_read_failure_closes_success_and_error_streams(urllib_transport, status, failure, args):
    transport = urllib_transport([(status, {}, b"{}")])
    transport.read_error = failure(*args)
    with pytest.raises(ProviderUnavailable) as error:
        _urllib_client().request("https://provider.synthetic.invalid/v1/chat/completions",
                                 data=b"{}", headers={}, timeout=1)
    assert transport.bodies[0].closed
    assert "synthetic-private-body" not in "".join(traceback.format_exception(error.value))


def test_provider_transport_failure_does_not_chain_private_details(monkeypatch):
    def fail(*args, **kwargs):
        raise urllib.error.URLError("synthetic-provider-key https://private.synthetic.invalid")

    monkeypatch.setattr(urllib.request, "urlopen", fail)
    monkeypatch.setattr(urllib.request.OpenerDirector, "open", fail)
    with pytest.raises(ProviderUnavailable) as error:
        _urllib_client().request("https://provider.synthetic.invalid/v1/chat/completions",
                                 data=b"{}", headers={}, timeout=1)
    rendered = "".join(traceback.format_exception(error.value))
    assert "synthetic-provider-key" not in rendered
    assert "private.synthetic.invalid" not in rendered


@pytest.mark.parametrize("url,local", [
    ("http://localhost:11434/v1/", True),
    ("http://LOCALHOST.:11434/v1/", True),
    ("http://127.0.0.1:11434/v1/", True),
    ("http://127.0.0.2:11434/v1/", True),
    ("http://[::1]:11434/v1/", True),
    ("https://provider-localhost.synthetic.invalid/v1/", False),
    ("https://127.0.0.1.synthetic.invalid/v1/", False),
    ("https://provider.synthetic.invalid/localhost/v1/", False),
    ("https://provider.synthetic.invalid/127.0.0.1/v1/", False),
])
def test_provider_locality_uses_the_host_instead_of_url_substrings(url, local):
    validated = Settings(llm_base_url=url).llm_base_url
    endpoint = _ProviderEndpoint(name="synthetic", model="synthetic", base_url=validated, api_key="synthetic")
    assert endpoint.is_local() is local


@pytest.mark.parametrize("url", ["https://provider-localhost.synthetic.invalid/v1/",
                                "https://provider.synthetic.invalid/localhost/v1/"])
def test_remote_provider_with_localhost_substring_retains_rate_limit_response(urllib_transport, url):
    urllib_transport([(429, {"Retry-After": "3600"}, b"{}")])
    service = LlmContentService(settings=provider_settings(llm_base_url=url))
    with pytest.raises(ProviderRateLimited) as error:
        service.generate(ContentRequest(text="station", kind="sentence"))
    assert error.value.retry_after_seconds == 3600


def test_provider_endpoint_repr_never_contains_credential():
    endpoint = _ProviderEndpoint(name="synthetic", model="synthetic",
                                 base_url="https://provider.synthetic.invalid/v1/",
                                 api_key="synthetic-provider-key")
    assert "synthetic-provider-key" not in repr(endpoint)
