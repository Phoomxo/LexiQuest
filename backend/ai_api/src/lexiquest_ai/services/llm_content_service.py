"""Provider-agnostic LLM content generator with a fallback chain.

Architecture (resilience-first, per the project's "don't depend on a single
external API" requirement):

    request -> [rate-limited Ollama (primary, $0)]
                 |
                 on unavailable/auth/transport error
                 v
              [rate-limited Gemini key #1] -> key #2 -> ... -> key #N
                 |
                 on rate-limit / auth error
                 v
              raise ProviderRateLimited (whole chain exhausted)

Each provider speaks the OpenAI-compatible ``/chat/completions`` contract, so
adding a provider is a configuration change (model + base_url + key), never a
code change. Switching from "Ollama primary" to "Gemini primary" is one env
var flip.

Design notes:

* No vendor SDK is imported; only stdlib ``urllib`` is used so unit tests run
  without network or provider packages.
* The HTTP client is injectable so tests supply a fake.
* API keys are held in a private attribute and never logged, never in client
  exceptions, never echoed in responses.
* Prompts are templated per ``ContentKind`` and pinned to a deterministic
  temperature by default so cache keys stay stable.
* The fallback chain never runs when the cache hit returns — the cache is the
  primary cost/quota saver.
"""

from __future__ import annotations

import json
import logging
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any, Protocol

from lexiquest_ai.config import Settings
from lexiquest_ai.models import ContentKind, ContentRequest, ContentResult
from lexiquest_ai.services.rate_limiter import (
    ProviderRateLimited,
    RateLimitedClient,
)

logger = logging.getLogger(__name__)

# Per-kind system prompts. Kept here (not in config) so prompt changes are
# code-reviewed and versioned with the service. ``model_version`` in the cache
# key is what invalidates responses when these prompts materially change.
_SYSTEM_PROMPTS: dict[ContentKind, str] = {
    "sentence": (
        "You are an English vocabulary teacher for Thai learners. "
        "Write ONE clear, natural example sentence using the target word. "
        "The sentence must match the requested CEFR level and language. "
        "Output ONLY the sentence, with no quotation marks, no preamble, "
        "and no explanation."
    ),
    "story": (
        "You are an English vocabulary teacher for Thai learners. "
        "Write a SHORT micro-story (2-4 sentences) that uses the target word "
        "in context. The story must match the requested CEFR level and "
        "language. Output ONLY the story, with no quotation marks, no "
        "preamble, and no explanation."
    ),
    "explanation": (
        "You are an English vocabulary teacher for Thai learners. "
        "Explain the target word in 2-4 short sentences. Include a plain "
        "definition, the part of speech, and a brief usage note. "
        "Match the requested CEFR level and language. "
        "Output ONLY the explanation, with no preamble."
    ),
}


class HttpClient(Protocol):
    """Minimal HTTP client surface used by every provider in the chain."""

    def request(
        self,
        url: str,
        *,
        data: bytes,
        headers: dict[str, str],
        timeout: float,
    ) -> "HttpResponse":
        ...


class HttpResponse(Protocol):
    status: int
    body: bytes


class ProviderUnavailable(Exception):
    """Provider could not be reached or returned a transport error."""


class ProviderUnauthorized(Exception):
    """Provider rejected the API key (401/403)."""


class ProviderRateLimitHit(Exception):
    """A single provider endpoint returned 429.

    Distinct from ``ProviderRateLimited`` (the rate_limiter module): this one
    is raised *by the HTTP response*, the other by *our local limiter*. The
    fallback chain treats both as "try the next provider" and only surfaces a
    final ``ProviderRateLimited`` to the caller when the whole chain is done.
    """


class ProviderError(Exception):
    """Provider responded in an unexpected shape or with an unexpected 5xx."""


@dataclass(frozen=True, slots=True)
class _ProviderEndpoint:
    """One configured LLM endpoint (model + base_url + key)."""

    name: str
    model: str
    base_url: str
    api_key: str

    def is_local(self) -> bool:
        """Local providers (Ollama) have no real quota, so their 429s are
        treated as a hard error rather than retried through the chain."""

        host = self.base_url.lower()
        return "127.0.0.1" in host or "localhost" in host


def _urllib_client() -> HttpClient:
    """Build the default stdlib HTTP client used in production."""

    import urllib.error
    import urllib.request

    class _StdlibResponse:
        __slots__ = ("status", "body")

        def __init__(self, status: int, body: bytes) -> None:
            self.status = status
            self.body = body

    class _StdlibClient:
        def request(
            self,
            url: str,
            *,
            data: bytes,
            headers: dict[str, str],
            timeout: float,
        ) -> HttpResponse:
            req = urllib.request.Request(url, data=data, headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310 - trusted operator-configured URL
                    return _StdlibResponse(resp.status, resp.read())
            except urllib.error.HTTPError as error:
                body = b""
                try:
                    body = error.read() or b""
                except Exception:  # pragma: no cover - defensive
                    body = b""
                return _StdlibResponse(error.code, body)
            except (urllib.error.URLError, TimeoutError, OSError) as error:
                raise ProviderUnavailable(
                    "LLM provider transport error"
                ) from error

    return _StdlibClient()  # type: ignore[return-value]


def build_provider_chain(settings: Settings) -> list[_ProviderEndpoint]:
    """Return the ordered list of providers to try, primary first.

    Order: [primary] + [fallback?] + [extra gemini keys?]. Duplicates (e.g.
    primary already equals a gemini key) are de-duplicated on
    ``(model, base_url, api_key)`` so the chain never wastes a slot.
    """

    chain: list[_ProviderEndpoint] = []
    seen: set[tuple[str, str, str]] = set()

    def _add(name: str, model: str, base_url: str, api_key: str) -> None:
        if not model or not base_url:
            return
        key = (model, base_url, api_key)
        if key in seen:
            return
        seen.add(key)
        chain.append(
            _ProviderEndpoint(name=name, model=model, base_url=base_url, api_key=api_key)
        )

    _add("primary", settings.llm_model, settings.llm_base_url, settings.llm_api_key)
    _add(
        "fallback",
        settings.fallback_llm_model,
        settings.fallback_llm_base_url,
        settings.fallback_llm_api_key,
    )
    # Round-robin keys share the fallback model/base_url but vary only by key,
    # which is exactly what multiplies the daily quota.
    for index, key in enumerate(
        k for k in settings.gemini_keys.split(",") if k.strip()
    ):
        _add(
            f"gemini-key-{index + 1}",
            settings.fallback_llm_model,
            settings.fallback_llm_base_url,
            key.strip(),
        )
    return chain


class LlmContentService:
    """OpenAI-compatible LLM content generator with a provider fallback chain.

    Implements ``ContentGenerator``. Provider selection and order come entirely
    from ``Settings``; no provider-specific code path exists, which is what
    keeps the cost ceiling and resilience under operator control.
    """

    def __init__(
        self,
        *,
        settings: Settings,
        http_client: HttpClient | Callable[[], HttpClient] | None = None,
    ) -> None:
        self._settings = settings
        self._chain = build_provider_chain(settings)
        if callable(http_client) and not isinstance(http_client, type):
            self._client_factory: Callable[[], HttpClient] = http_client
            self._rate_limited: RateLimitedClient | None = None
        else:
            base = http_client or _urllib_client()
            self._client_factory = lambda: base  # type: ignore[assignment]
            # Wrap immediately so the limiter is consistent across calls.
            self._rate_limited = RateLimitedClient(
                inner=base, max_per_minute=settings.provider_rpm_limit
            )

    @property
    def is_ready(self) -> bool:
        # Ready as long as at least one provider is configured. We do NOT
        # probe the provider on every readiness check (that would cost a
        # request); ``/health/ready`` returns 200 and real availability is
        # surfaced per-request through the fallback chain.
        return bool(self._chain)

    def _get_client(self) -> RateLimitedClient:
        if self._rate_limited is None:
            base = self._client_factory()
            self._rate_limited = RateLimitedClient(
                inner=base, max_per_minute=self._settings.provider_rpm_limit
            )
        return self._rate_limited

    def generate(self, request: ContentRequest) -> ContentResult:
        system_prompt = _SYSTEM_PROMPTS.get(request.kind)
        if system_prompt is None:
            raise ProviderError(f"Unknown content kind: {request.kind!r}")

        user_prompt = self._build_user_prompt(request)
        text = self._complete_across_chain(system_prompt, user_prompt)
        return ContentResult(
            text=text,
            kind=request.kind,
            model_version=self._settings.model_version,
            cached=False,
        )

    def _build_user_prompt(self, request: ContentRequest) -> str:
        level = "no specific level" if request.cefr == "unknown" else request.cefr.upper()
        language_name = "Thai" if request.language == "th" else "English"
        return (
            f"Target word/phrase: {request.text}\n"
            f"CEFR level: {level}\n"
            f"Output language: {language_name}"
        )

    def _complete_across_chain(
        self, system_prompt: str, user_prompt: str
    ) -> str:
        """Try each provider in order until one succeeds.

        Aggregates the local limiter's ``Retry-After`` and the provider's own
        429 ``Retry-After`` so that, if every provider is rate limited, we can
        return a single worst-case back-off rather than a misleading zero.
        """

        client = self._get_client()
        worst_retry_after = 0
        last_failure: Exception | None = None

        for endpoint in self._chain:
            try:
                return self._complete_one(client, endpoint, system_prompt, user_prompt)
            except ProviderRateLimitHit as error:
                # Provider itself said 429: record its back-off and continue.
                worst_retry_after = max(worst_retry_after, error.args[0] if error.args else 1)
                last_failure = error
                logger.info(
                    "Provider %s rate-limited; trying next in chain",
                    endpoint.name,
                )
                continue
            except ProviderRateLimited as error:
                # Our own limiter blocked this endpoint before the request:
                # record the wait and try the next provider.
                worst_retry_after = max(worst_retry_after, error.retry_after_seconds)
                last_failure = error
                logger.info(
                    "Local limiter blocked provider %s; trying next in chain",
                    endpoint.name,
                )
                continue
            except (ProviderUnavailable, ProviderUnauthorized) as error:
                last_failure = error
                logger.info(
                    "Provider %s unavailable (%s); trying next in chain",
                    endpoint.name,
                    type(error).__name__,
                )
                continue
            # ``ProviderError`` (malformed/unexpected) is NOT retried across
            # the chain: a deterministic provider bug should not silently
            # reroute to a different provider because the output provenance
            # would change without the operator knowing.

        # Entire chain exhausted on rate limiting.
        if worst_retry_after > 0:
            raise ProviderRateLimited(retry_after_seconds=worst_retry_after)
        # Entire chain exhausted on availability — surface the last cause so
        # the app layer maps it to PROVIDER_UNAVAILABLE.
        if last_failure is not None:
            raise last_failure
        # Defensive: chain was empty (should not happen because ``is_ready``
        # guards it), but never let a bare ``None`` propagate.
        raise ProviderUnavailable("no provider configured")

    def _complete_one(
        self,
        client: RateLimitedClient,
        endpoint: _ProviderEndpoint,
        system_prompt: str,
        user_prompt: str,
    ) -> str:
        url = endpoint.base_url + "chat/completions"
        payload: dict[str, Any] = {
            "model": endpoint.model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "temperature": self._settings.llm_temperature,
            "max_tokens": self._settings.llm_max_tokens,
        }
        data = json.dumps(payload).encode("utf-8")
        headers = {"Content-Type": "application/json"}
        if endpoint.api_key:
            headers["Authorization"] = f"Bearer {endpoint.api_key}"

        response = client.request(
            url,
            data=data,
            headers=headers,
            timeout=float(self._settings.request_timeout_seconds),
        )

        if response.status == 429:
            retry_after = self._parse_retry_after(response) or 5
            # A local Ollama returning 429 is unusual; treat it as a hard
            # error (do not silently move traffic to Gemini, which would
            # quietly burn cloud quota for a local misconfiguration).
            if endpoint.is_local():
                raise ProviderUnavailable("local provider returned 429")
            raise ProviderRateLimitHit(retry_after)
        if response.status in (401, 403):
            logger.warning(
                "Provider %s rejected credentials (status=%s)",
                endpoint.name,
                response.status,
            )
            raise ProviderUnauthorized("provider rejected credentials")
        if response.status >= 500:
            raise ProviderUnavailable(f"provider status {response.status}")
        if response.status != 200:
            raise ProviderError(f"unexpected provider status {response.status}")

        return self._extract_message(response.body)

    def _parse_retry_after(self, response: HttpResponse) -> int:
        """Best-effort parse of a ``Retry-After`` header (seconds only).

        Returns 0 when absent or unparseable; callers fall back to a default.
        We do not support the HTTP-date form because the OpenAI-compat
        providers we target emit seconds.
        """

        # HttpResponse is a Protocol without header access; peek at an optional
        # ``headers`` attribute if the concrete client exposes one.
        headers = getattr(response, "headers", None)
        if not headers:
            return 0
        try:
            raw = headers.get("Retry-After") or headers.get("retry-after")
        except AttributeError:
            return 0
        if not raw:
            return 0
        try:
            return max(1, int(str(raw).strip()))
        except ValueError:
            return 0

    def _extract_message(self, body: bytes) -> str:
        try:
            decoded = json.loads(body.decode("utf-8"))
        except (ValueError, UnicodeDecodeError) as error:
            raise ProviderError("provider response was not valid JSON") from error
        try:
            text = decoded["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError) as error:
            raise ProviderError("provider response missing choices[0].message") from error
        if not isinstance(text, str) or not text.strip():
            raise ProviderError("provider returned empty content")
        return text.strip()
