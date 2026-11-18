from pydantic import BaseModel


class InfoResponse(BaseModel):
    environment: str
    version: str
