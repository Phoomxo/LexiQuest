"""Bound the real urllib response reader without contacting a provider."""
import io
from email.message import Message
from urllib.error import HTTPError
from urllib.response import addinfourl

import pytest

from lexiquest_ai.services.llm_content_service import ProviderError, _urllib_client


@pytest.mark.parametrize("status", [200, 429, 503])
def test_oversized_provider_response_is_bounded_and_closed(monkeypatch, status):
    sizes = []

    class RecordingBody(io.BytesIO):
        def read(self, size=-1):
            sizes.append(size)
            return super().read(size)

    body = RecordingBody(b"x" * (1_048_576 + 2))

    def open_response(request, *, timeout):
        if status != 200:
            raise HTTPError(request.full_url, status, "synthetic", Message(), body)
        return addinfourl(body, Message(), request.full_url, code=status)

    monkeypatch.setattr("urllib.request.urlopen", open_response)
    with pytest.raises(ProviderError, match="response exceeds"):
        _urllib_client().request(
            "https://provider.example/v1/chat/completions",
            data=b"{}", headers={}, timeout=1,
        )
    assert sizes == [1_048_577]
    assert body.closed
