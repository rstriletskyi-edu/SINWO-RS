from configs.settings import Settings
from models.info import InfoResponse


class InfoService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    def get_info(self) -> InfoResponse:
        return InfoResponse(
            environment=self._settings.app_env,
            version=self._settings.app_version,
        )
