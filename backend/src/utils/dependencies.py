from fastapi import Depends, Request

from configs.settings import Settings, get_settings
from repositories.task_repository import TaskRepository
from services.info_service import InfoService
from services.task_service import TaskService


def get_task_repository(request: Request) -> TaskRepository:
    return request.app.state.task_repository


def get_task_service(
    repository: TaskRepository = Depends(get_task_repository),
) -> TaskService:
    return TaskService(repository)


def get_info_service(settings: Settings = Depends(get_settings)) -> InfoService:
    return InfoService(settings)
