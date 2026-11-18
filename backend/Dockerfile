# syntax=docker/dockerfile:1

FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    POETRY_VERSION=2.5.1 \
    POETRY_VIRTUALENVS_IN_PROJECT=1 \
    POETRY_NO_INTERACTION=1

FROM base AS builder

WORKDIR /app
RUN pip install --no-cache-dir "poetry==${POETRY_VERSION}"
COPY pyproject.toml poetry.lock ./

FROM builder AS builder-dev

RUN poetry install --with dev --no-root

FROM builder AS builder-prod

RUN poetry install --only main --no-root

FROM base AS dev

WORKDIR /app
COPY --from=builder-dev /app/.venv /app/.venv
COPY src ./src
ENV PYTHONPATH=/app/src \
    PATH="/app/.venv/bin:${PATH}"
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]

FROM python:3.12-slim AS prod

WORKDIR /app
RUN useradd --create-home --uid 10001 appuser
COPY --from=builder-prod /app/.venv /app/.venv
COPY src ./src
ENV PYTHONPATH=/app/src \
    PATH="/app/.venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
USER appuser
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
