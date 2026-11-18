from datetime import UTC, datetime
from uuid import uuid4

from models.task import TaskCreateRequest, TaskResponse, TaskUpdateRequest


class TaskRepository:
    """In-memory task store. State lives for the process lifetime."""

    def __init__(self) -> None:
        self._tasks: dict[str, TaskResponse] = {}

    def list_tasks(self) -> list[TaskResponse]:
        return sorted(self._tasks.values(), key=lambda task: task.created_at)

    def get_task(self, task_id: str) -> TaskResponse | None:
        return self._tasks.get(task_id)

    def create_task(self, payload: TaskCreateRequest) -> TaskResponse:
        task = TaskResponse(
            id=str(uuid4()),
            title=payload.title,
            description=payload.description,
            completed=False,
            created_at=datetime.now(UTC),
        )
        self._tasks[task.id] = task
        return task

    def update_task(self, task_id: str, payload: TaskUpdateRequest) -> TaskResponse | None:
        current = self._tasks.get(task_id)
        if current is None:
            return None

        updated = current.model_copy(
            update={
                "title": current.title if payload.title is None else payload.title,
                "description": (
                    current.description if payload.description is None else payload.description
                ),
                "completed": current.completed if payload.completed is None else payload.completed,
            }
        )
        self._tasks[task_id] = updated
        return updated

    def delete_task(self, task_id: str) -> bool:
        return self._tasks.pop(task_id, None) is not None

    def clear(self) -> None:
        self._tasks.clear()
