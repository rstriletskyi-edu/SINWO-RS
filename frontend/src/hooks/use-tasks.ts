import { useCallback, useEffect, useState } from "react"
import { toast } from "sonner"

import { api } from "@/lib/api"
import type { Task, TaskCreateRequest } from "@/types/task"

function errorMessage(caught: unknown, fallback: string): string {
  return caught instanceof Error ? caught.message : fallback
}

export function useTasks() {
  const [tasks, setTasks] = useState<Task[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const refresh = useCallback(async () => {
    setLoading(true)
    try {
      setTasks(await api.listTasks())
      setError(null)
    } catch (caught) {
      setError(errorMessage(caught, "Unable to load tasks"))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    let active = true

    void (async () => {
      try {
        const next = await api.listTasks()
        if (!active) {
          return
        }
        setTasks(next)
        setError(null)
      } catch (caught) {
        if (!active) {
          return
        }
        setError(errorMessage(caught, "Unable to load tasks"))
      } finally {
        if (active) {
          setLoading(false)
        }
      }
    })()

    return () => {
      active = false
    }
  }, [])

  const createTask = useCallback(async (payload: TaskCreateRequest) => {
    try {
      const created = await api.createTask(payload)
      setTasks((current) => [...current, created])
      toast.success("Task created")
      return true
    } catch (caught) {
      toast.error(errorMessage(caught, "Unable to create task"))
      return false
    }
  }, [])

  const toggleTask = useCallback(async (task: Task) => {
    try {
      const updated = await api.updateTask(task.id, { completed: !task.completed })
      setTasks((current) => current.map((item) => (item.id === updated.id ? updated : item)))
      toast.success(updated.completed ? "Task completed" : "Task reopened")
    } catch (caught) {
      toast.error(errorMessage(caught, "Unable to update task"))
    }
  }, [])

  const deleteTask = useCallback(async (task: Task) => {
    try {
      await api.deleteTask(task.id)
      setTasks((current) => current.filter((item) => item.id !== task.id))
      toast.success("Task deleted")
    } catch (caught) {
      toast.error(errorMessage(caught, "Unable to delete task"))
    }
  }, [])

  return { tasks, loading, error, createTask, toggleTask, deleteTask, refresh }
}
