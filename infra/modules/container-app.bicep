@description('Container App name.')
param name string

@description('Azure region. Must match the Container Apps environment.')
param location string

@description('Resource ID of the shared Container Apps environment.')
param environmentId string

@description('Resource ID of the user-assigned identity that has AcrPull on the registry.')
param identityId string

@description('ACR login server, for example acrsinwo.azurecr.io.')
param registryLoginServer string

@description('Full image reference, including the registry and tag.')
param image string

@description('Value that changes on every deployment so Container Apps creates a revision and pulls the tag again.')
param deployStamp string

@description('Container name inside the app.')
param containerName string

@description('Port the container listens on.')
param targetPort int

@description('HTTP path used by the liveness and readiness probes.')
param probePath string

@description('Environment variables injected into the container.')
param containerEnv array

@description('Upper scale limit. Minimum stays at 0 so an idle app has no replica charge.')
param maxReplicas int

@description('Tags applied to the Container App.')
param tags object

resource app 'Microsoft.App/containerApps@2026-07-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: [
        {
          server: registryLoginServer
          identity: identityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: containerName
          image: image
          env: concat(containerEnv, [
            { name: 'DEPLOY_STAMP', value: deployStamp }
          ])
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: probePath
                port: targetPort
              }
              initialDelaySeconds: 10
              periodSeconds: 30
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: probePath
                port: targetPort
              }
              initialDelaySeconds: 5
              periodSeconds: 10
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
output url string = 'https://${app.properties.configuration.ingress.fqdn}'
