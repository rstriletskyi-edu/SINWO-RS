import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { beforeEach, expect, test, vi } from "vitest"

import { TasksPage } from "@/features/tasks/tasks-page"
import { api } from "@/lib/api"
import type { Task } from "@/types/task"

vi.mock("@/lib/api", () => ({
  api: {
    listTasks: vi.fn(),
    createTask: vi.fn(),
    updateTask: vi.fn(),
    deleteTask: vi.fn(),
  },
}))

vi.mock("sonner", () => ({
  toast: {
    success: vi.fn(),
    error: vi.fn(),
  },
}))

const existingTask: Task = {
  id: "1",
  title: "Write tests",
  description: "Cover the page",
  completed: false,
  created_at: "2026-01-01T00:00:00Z",
}

beforeEach(() => {
  vi.mocked(api.listTasks).mockResolvedValue([existingTask])
  vi.mocked(api.createTask).mockResolvedValue({
    id: "2",
    title: "Ship it",
    description: "",
    completed: false,
    created_at: "2026-01-02T00:00:00Z",
  })
})

test("lists tasks and creates a new one", async () => {
  const user = userEvent.setup()
  render(<TasksPage />)

  expect(await screen.findByText("Write tests")).toBeInTheDocument()

  await user.type(screen.getByLabelText("Title"), "Ship it")
  await user.click(screen.getByRole("button", { name: "Add task" }))

  expect(await screen.findByText("Ship it")).toBeInTheDocument()
  expect(api.createTask).toHaveBeenCalledWith({ title: "Ship it", description: "" })
})

test("shows an empty state when the API returns no tasks", async () => {
  vi.mocked(api.listTasks).mockResolvedValue([])
  render(<TasksPage />)

  expect(await screen.findByText("No tasks yet.")).toBeInTheDocument()
})
