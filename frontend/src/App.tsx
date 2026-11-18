import { LayoutDashboard, ListTodo } from "lucide-react"
import { useState } from "react"

import { Separator } from "@/components/ui/separator"
import {
  Sidebar,
  SidebarContent,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarInset,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarProvider,
  SidebarTrigger,
} from "@/components/ui/sidebar"
import { DashboardPage } from "@/features/dashboard/dashboard-page"
import { TasksPage } from "@/features/tasks/tasks-page"

type View = "dashboard" | "tasks"

const views = [
  { id: "dashboard", label: "Dashboard", icon: LayoutDashboard },
  { id: "tasks", label: "Tasks", icon: ListTodo },
] as const

export function App() {
  const [view, setView] = useState<View>("dashboard")
  const current = views.find((item) => item.id === view) ?? views[0]

  return (
    <SidebarProvider>
      <Sidebar>
        <SidebarHeader className="gap-1 p-4">
          <span className="text-sm font-semibold">SINWO</span>
          <span className="text-xs text-muted-foreground">CI/CD showcase</span>
        </SidebarHeader>
        <SidebarContent>
          <SidebarGroup>
            <SidebarGroupLabel>Navigate</SidebarGroupLabel>
            <SidebarGroupContent>
              <SidebarMenu>
                {views.map((item) => (
                  <SidebarMenuItem key={item.id}>
                    <SidebarMenuButton isActive={view === item.id} onClick={() => setView(item.id)}>
                      <item.icon className="size-4" />
                      <span>{item.label}</span>
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                ))}
              </SidebarMenu>
            </SidebarGroupContent>
          </SidebarGroup>
        </SidebarContent>
      </Sidebar>
      <SidebarInset>
        <header className="flex h-14 items-center gap-2 border-b border-border px-4">
          <SidebarTrigger />
          <Separator orientation="vertical" className="h-4" />
          <p className="text-sm font-medium">{current.label}</p>
        </header>
        <main className="flex flex-1 flex-col p-6">{view === "dashboard" ? <DashboardPage /> : <TasksPage />}</main>
      </SidebarInset>
    </SidebarProvider>
  )
}
