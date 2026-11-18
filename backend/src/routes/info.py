from fastapi import APIRouter, Depends

from models.info import InfoResponse
from services.info_service import InfoService
from utils.dependencies import get_info_service

router = APIRouter(tags=["info"])


@router.get("/info", response_model=InfoResponse)
async def info(service: InfoService = Depends(get_info_service)) -> InfoResponse:
    return service.get_info()
