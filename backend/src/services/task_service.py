from models.task import TaskCreateRequest, TaskResponse, TaskUpdateRequest
from repositories.task_repository import TaskRepository
from utils.exceptions import DomainError, TaskNotFoundError


class TaskService:
    def __init__(self, repository: TaskRepository) -> None:
        self._repository = repository

    def list_tasks(self) -> list[TaskResponse]:
        return self._repository.list_tasks()

    def get_task(self, task_id: str) -> TaskResponse:
        task = self._repository.get_task(task_id)
        if task is None:
            raise TaskNotFoundError(f"Task {task_id} was not found")
        return task

    def create_task(self, payload: TaskCreateRequest) -> TaskResponse:
        normalized = payload.model_copy(
            update={
                "title": payload.title.strip(),
                "description": payload.description.strip(),
            }
        )
        if not normalized.title:
            raise DomainError("Title is required")
        return self._repository.create_task(normalized)

    def update_task(self, task_id: str, payload: TaskUpdateRequest) -> TaskResponse:
        if payload.title is None and payload.description is None and payload.completed is None:
            raise DomainError("At least one field must be provided")

        updates: dict[str, str] = {}
        if payload.title is not None:
            title = payload.title.strip()
            if not title:
                raise DomainError("Title is required")
            updates["title"] = title
        if payload.description is not None:
            updates["description"] = payload.description.strip()

        normalized = payload.model_copy(update=updates)
        updated = self._repository.update_task(task_id, normalized)
        if updated is None:
            raise TaskNotFoundError(f"Task {task_id} was not found")
        return updated

    def delete_task(self, task_id: str) -> None:
        if not self._repository.delete_task(task_id):
            raise TaskNotFoundError(f"Task {task_id} was not found")
