class DomainError(Exception):
    """Base class for domain failures mapped to HTTP responses."""

    def __init__(self, message: str) -> None:
        self.message = message
        super().__init__(message)


class TaskNotFoundError(DomainError):
    """Raised when a task id does not exist."""
