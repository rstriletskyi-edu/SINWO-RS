import type { HealthResponse } from "@/types/health"
import type { InfoResponse } from "@/types/info"
import type { Task, TaskCreateRequest, TaskUpdateRequest } from "@/types/task"

export class ApiError extends Error {
  readonly status: number

  constructor(message: string, status: number) {
    super(message)
    this.name = "ApiError"
    this.status = status
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, {
    ...init,
    headers: {
      Accept: "application/json",
      ...(init?.body ? { "Content-Type": "application/json" } : {}),
      ...init?.headers,
    },
  })

  if (!response.ok) {
    let detail = response.statusText
    try {
      const body = (await response.json()) as { detail?: string }
      if (body.detail) {
        detail = body.detail
      }
    } catch {
      detail = response.statusText
    }
    throw new ApiError(detail || "Request failed", response.status)
  }

  if (response.status === 204) {
    return undefined as T
  }

  return (await response.json()) as T
}

export const api = {
  getHealth: () => request<HealthResponse>("/api/health"),
  getInfo: () => request<InfoResponse>("/api/info"),
  listTasks: () => request<Task[]>("/api/tasks"),
  createTask: (payload: TaskCreateRequest) =>
    request<Task>("/api/tasks", {
      method: "POST",
      body: JSON.stringify(payload),
    }),
  updateTask: (taskId: string, payload: TaskUpdateRequest) =>
    request<Task>(`/api/tasks/${taskId}`, {
      method: "PATCH",
      body: JSON.stringify(payload),
    }),
  deleteTask: (taskId: string) =>
    request<void>(`/api/tasks/${taskId}`, {
      method: "DELETE",
    }),
}
