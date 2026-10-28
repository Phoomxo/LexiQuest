"""LexiQuest AI API.

Provider-agnostic LLM content generation service for the LexiQuest vocabulary
learning application. Sibling to ``lexiquest_voice``; mirrors its FastAPI +
``TokenVerifier`` + stable-error conventions so the two services compose
identically from the client's perspective.
"""

__all__ = ["__version__"]

__version__ = "0.1.0"
