from fastapi import HTTPException, status


def model_unavailable() -> HTTPException:
    """Return the stable readiness error exposed by the API."""

    return HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail={
            "code": "MODEL_UNAVAILABLE",
            "message": "The speech engine is not ready.",
        },
    )
