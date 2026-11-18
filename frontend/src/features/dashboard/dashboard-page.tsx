import { useEffect, useState } from "react"

import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { api } from "@/lib/api"
import type { HealthResponse } from "@/types/health"
import type { InfoResponse } from "@/types/info"

export function DashboardPage() {
  const [info, setInfo] = useState<InfoResponse | null>(null)
  const [health, setHealth] = useState<HealthResponse | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let active = true

    Promise.all([api.getInfo(), api.getHealth()])
      .then(([infoResponse, healthResponse]) => {
        if (!active) {
          return
        }
        setInfo(infoResponse)
        setHealth(healthResponse)
      })
      .catch((caught: unknown) => {
        if (!active) {
          return
        }
        setError(caught instanceof Error ? caught.message : "Unable to reach the API")
      })

    return () => {
      active = false
    }
  }, [])

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-2">
        <h1 className="text-2xl font-semibold tracking-tight">Dashboard</h1>
        <p className="text-muted-foreground">Live environment and version reported by the API.</p>
      </div>

      {error ? <p className="text-sm text-destructive">{error}</p> : null}

      <Tabs defaultValue="overview">
        <TabsList>
          <TabsTrigger value="overview">Overview</TabsTrigger>
          <TabsTrigger value="runtime">Runtime</TabsTrigger>
        </TabsList>
        <TabsContent value="overview" className="grid gap-4 md:grid-cols-3">
          <Card>
            <CardHeader>
              <CardDescription>API status</CardDescription>
              <CardTitle>{health?.status === "ok" ? "Reachable" : "Checking"}</CardTitle>
            </CardHeader>
            <CardContent>
              <Badge variant={health?.status === "ok" ? "secondary" : "outline"}>
                {health?.status ?? "pending"}
              </Badge>
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardDescription>Environment</CardDescription>
              <CardTitle>{info?.environment ?? "Unknown"}</CardTitle>
            </CardHeader>
            <CardContent>
              {info ? (
                <Badge variant={info.environment === "PROD" ? "prod" : "dev"}>{info.environment}</Badge>
              ) : (
                <p className="text-sm text-muted-foreground">Waiting for the API</p>
              )}
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardDescription>Deployed version</CardDescription>
              <CardTitle>{info?.version ?? "Unknown"}</CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-sm text-muted-foreground">Image version supplied by APP_VERSION.</p>
            </CardContent>
          </Card>
        </TabsContent>
        <TabsContent value="runtime">
          <Card>
            <CardHeader>
              <CardTitle>Runtime summary</CardTitle>
              <CardDescription>Values the pipeline injects when this image is deployed.</CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-2">
              <p className="text-sm">Environment: {info?.environment ?? "Unknown"}</p>
              <p className="text-sm">Version: {info?.version ?? "Unknown"}</p>
              <p className="text-sm text-muted-foreground">
                DEV and PROD run the same frontend image with a different backend URL.
              </p>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  )
}
