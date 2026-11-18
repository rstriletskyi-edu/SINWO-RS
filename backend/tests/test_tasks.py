from httpx import AsyncClient


async def test_task_crud(client: AsyncClient) -> None:
    empty = await client.get("/api/tasks")
    assert empty.status_code == 200
    assert empty.json() == []

    created = await client.post(
        "/api/tasks",
        json={"title": "  Ship the pipeline  ", "description": "  Document the flow  "},
    )
    assert created.status_code == 201
    body = created.json()
    assert body["title"] == "Ship the pipeline"
    assert body["description"] == "Document the flow"
    assert body["completed"] is False
    task_id = body["id"]

    fetched = await client.get(f"/api/tasks/{task_id}")
    assert fetched.status_code == 200
    assert fetched.json()["id"] == task_id

    updated = await client.patch(
        f"/api/tasks/{task_id}",
        json={"completed": True, "title": "Ship the pipeline"},
    )
    assert updated.status_code == 200
    assert updated.json()["completed"] is True

    listed = await client.get("/api/tasks")
    assert listed.status_code == 200
    assert len(listed.json()) == 1

    deleted = await client.delete(f"/api/tasks/{task_id}")
    assert deleted.status_code == 204

    missing = await client.get(f"/api/tasks/{task_id}")
    assert missing.status_code == 404


async def test_task_not_found(client: AsyncClient) -> None:
    missing_id = "00000000-0000-0000-0000-000000000000"

    fetched = await client.get(f"/api/tasks/{missing_id}")
    updated = await client.patch(f"/api/tasks/{missing_id}", json={"completed": True})
    deleted = await client.delete(f"/api/tasks/{missing_id}")

    assert fetched.status_code == 404
    assert updated.status_code == 404
    assert deleted.status_code == 404


async def test_empty_update_is_rejected(client: AsyncClient) -> None:
    created = await client.post("/api/tasks", json={"title": "Keep one field"})
    task_id = created.json()["id"]

    response = await client.patch(f"/api/tasks/{task_id}", json={})

    assert response.status_code == 400
    assert response.json()["detail"] == "At least one field must be provided"


async def test_blank_title_is_rejected(client: AsyncClient) -> None:
    response = await client.post("/api/tasks", json={"title": "   "})

    assert response.status_code == 400
    assert response.json()["detail"] == "Title is required"
