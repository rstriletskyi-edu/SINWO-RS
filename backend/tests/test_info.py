import pytest
from httpx import AsyncClient

from configs.settings import get_settings


async def test_info_defaults(client: AsyncClient) -> None:
    get_settings.cache_clear()
    response = await client.get("/api/info")

    assert response.status_code == 200
    assert response.json() == {"environment": "DEV", "version": "0.1.0"}


async def test_info_reads_environment(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("APP_ENV", "PROD")
    monkeypatch.setenv("APP_VERSION", "v1.2.3")
    get_settings.cache_clear()
    try:
        response = await client.get("/api/info")
        assert response.status_code == 200
        assert response.json() == {"environment": "PROD", "version": "v1.2.3"}
    finally:
        get_settings.cache_clear()
