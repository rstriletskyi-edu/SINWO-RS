from collections.abc import AsyncIterator

import pytest
from httpx import ASGITransport, AsyncClient

from main import create_app


@pytest.fixture
async def client() -> AsyncIterator[AsyncClient]:
    application = create_app()
    async with application.router.lifespan_context(application):
        transport = ASGITransport(app=application)
        async with AsyncClient(transport=transport, base_url="http://test") as async_client:
            yield async_client
