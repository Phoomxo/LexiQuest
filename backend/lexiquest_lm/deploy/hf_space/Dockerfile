FROM python:3.11.14-slim-bookworm@sha256:65a93d69fa75478d554f4ad27c85c1e69fa184956261b4301ebaf6dbb0a3543d

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

RUN groupadd --system --gid 1000 app \
 && useradd --system --uid 1000 --gid app --home-dir /home/app \
      --create-home --shell /usr/sbin/nologin app

WORKDIR /home/app

COPY --chown=app:app requirements.txt ./
RUN pip install --no-cache-dir --requirement requirements.txt

COPY --chown=app:app app.py auth.py README.md ./

USER app

EXPOSE 7860

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD python -c "import sys, urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:7860/health/live', timeout=3).status == 200 else 1)"

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "7860"]
