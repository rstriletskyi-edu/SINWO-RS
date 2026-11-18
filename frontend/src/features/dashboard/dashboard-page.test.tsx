import { render, screen } from "@testing-library/react"
import { beforeEach, expect, test, vi } from "vitest"

import { DashboardPage } from "@/features/dashboard/dashboard-page"
import { api } from "@/lib/api"

vi.mock("@/lib/api", () => ({
  api: {
    getInfo: vi.fn(),
    getHealth: vi.fn(),
  },
}))

beforeEach(() => {
  vi.mocked(api.getInfo).mockResolvedValue({ environment: "DEV", version: "v1.0.0" })
  vi.mocked(api.getHealth).mockResolvedValue({ status: "ok" })
})

test("shows the environment badge and deployed version", async () => {
  render(<DashboardPage />)

  expect(await screen.findByText("v1.0.0")).toBeInTheDocument()
  expect(screen.getAllByText("DEV").length).toBeGreaterThan(0)
  expect(screen.getByText("ok")).toBeInTheDocument()
})

test("shows an error when the API is unreachable", async () => {
  vi.mocked(api.getInfo).mockRejectedValue(new Error("network down"))
  vi.mocked(api.getHealth).mockRejectedValue(new Error("network down"))

  render(<DashboardPage />)

  expect(await screen.findByText("network down")).toBeInTheDocument()
})
