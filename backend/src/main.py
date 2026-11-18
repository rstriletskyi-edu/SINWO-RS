from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from repositories.task_repository import TaskRepository
from routes.health import router as health_router
from routes.info import router as info_router
from routes.tasks import router as tasks_router
from utils.exceptions import DomainError, TaskNotFoundError


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    app.state.task_repository = TaskRepository()
    yield


def create_app() -> FastAPI:
    app = FastAPI(title="SINWO API", lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["http://localhost:5173", "http://127.0.0.1:5173"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(health_router, prefix="/api")
    app.include_router(info_router, prefix="/api")
    app.include_router(tasks_router, prefix="/api")
    app.add_exception_handler(TaskNotFoundError, task_not_found_handler)
    app.add_exception_handler(DomainError, domain_error_handler)
    return app


async def task_not_found_handler(_: Request, exc: TaskNotFoundError) -> JSONResponse:
    return JSONResponse(status_code=404, content={"detail": exc.message})


async def domain_error_handler(_: Request, exc: DomainError) -> JSONResponse:
    return JSONResponse(status_code=400, content={"detail": exc.message})


app = create_app()
