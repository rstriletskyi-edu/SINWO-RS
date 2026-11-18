from fastapi import APIRouter, Depends, Response, status

from models.task import TaskCreateRequest, TaskResponse, TaskUpdateRequest
from services.task_service import TaskService
from utils.dependencies import get_task_service

router = APIRouter(prefix="/tasks", tags=["tasks"])


@router.get("", response_model=list[TaskResponse])
async def list_tasks(service: TaskService = Depends(get_task_service)) -> list[TaskResponse]:
    return service.list_tasks()


@router.post("", response_model=TaskResponse, status_code=status.HTTP_201_CREATED)
async def create_task(
    payload: TaskCreateRequest,
    service: TaskService = Depends(get_task_service),
) -> TaskResponse:
    return service.create_task(payload)


@router.get("/{task_id}", response_model=TaskResponse)
async def get_task(
    task_id: str,
    service: TaskService = Depends(get_task_service),
) -> TaskResponse:
    return service.get_task(task_id)


@router.patch("/{task_id}", response_model=TaskResponse)
async def update_task(
    task_id: str,
    payload: TaskUpdateRequest,
    service: TaskService = Depends(get_task_service),
) -> TaskResponse:
    return service.update_task(task_id, payload)


@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_task(
    task_id: str,
    service: TaskService = Depends(get_task_service),
) -> Response:
    service.delete_task(task_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
