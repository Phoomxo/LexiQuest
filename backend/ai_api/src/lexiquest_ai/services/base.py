"""Provider-neutral content generation protocol.

The HTTP layer depends on ``ContentGenerator`` so tests can inject a fake
generator that runs without network access or an LLM API key, exactly mirroring
the ``SpeechEngine`` boundary in ``lexiquest_voice``.
"""

from __future__ import annotations

from typing import Protocol

from lexiquest_ai.models import ContentRequest, ContentResult


class ContentGenerator(Protocol):
    """Boundary that turns a validated request into generated text."""

    @property
    def is_ready(self) -> bool:
        """Whether the provider is loaded and ready to serve requests."""

        ...

    def generate(self, request: ContentRequest) -> ContentResult:
        """Generate content for a validated request.

        The returned ``ContentResult.cached`` is always ``False`` from the
        provider; the cache layer in ``CachingContentGenerator`` is responsible
        for flipping it to ``True`` on cache hits.
        """

        ...
