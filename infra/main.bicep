targetScope = 'resourceGroup'

@description('Region for every resource. ACR webhooks must be created in the registry region.')
param location string

@description('Globally unique ACR name, 5-50 alphanumeric characters.')
@minLength(5)
@maxLength(50)
param acrName string

@description('Shared Container Apps environment.')
param environmentName string = 'cae-sinwo'

@description('User-assigned identity used by all four apps to pull images.')
param pullIdentityName string = 'id-sinwo-acr-pull'

@description('Log Analytics workspace that receives Container Apps logs.')
param logAnalyticsName string = 'log-sinwo-cicd'

@description('Built-in AcrPull role definition ID.')
param acrPullRoleId string = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

@description('Maximum replicas for each app. Minimum is fixed at 0.')
param maxReplicas int = 1

param backendRepository string = 'sinwo-backend'
param frontendRepository string = 'sinwo-frontend'
param devTag string = 'dev-latest'
param prodTag string = 'prod-latest'

param backendDevName string = 'ca-backend-dev'
param frontendDevName string = 'ca-frontend-dev'
param backendProdName string = 'ca-backend-prod'
param frontendProdName string = 'ca-frontend-prod'

var projectTag = {
  project: 'sinwo-cicd'
}

resource pullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: pullIdentityName
  location: location
  tags: projectTag
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: projectTag
  sku: {
    name: 'Basic'
  }
  properties: {
    // Phase 1: GitHub Actions logs in with the admin user because the university tenant
    // blocks Entra app registrations. Phase 2 turns this off and uses OIDC.
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
  }
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, pullIdentity.id, acrPullRoleId)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: pullIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: projectTag
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

param deployStamp string

// Without an explicit mode, Azure creates an Express environment, which cannot pull
// private ACR images through a managed identity.
resource environment 'Microsoft.App/managedEnvironments@2026-07-01' = {
  name: environmentName
  location: location
  tags: projectTag
  properties: {
    environmentMode: 'WorkloadProfiles'
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

module backendDev 'modules/container-app.bicep' = {
  name: 'ca-backend-dev'
  params: {
    name: backendDevName
    location: location
    environmentId: environment.id
    identityId: pullIdentity.id
    registryLoginServer: registry.properties.loginServer
    deployStamp: deployStamp
    image: '${registry.properties.loginServer}/${backendRepository}:${devTag}'
    containerName: 'backend'
    targetPort: 8000
    probePath: '/api/health'
    maxReplicas: maxReplicas
    tags: union(projectTag, { environment: 'DEV' })
    containerEnv: [
      { name: 'APP_ENV', value: 'DEV' }
      { name: 'APP_VERSION', value: devTag }
    ]
  }
  dependsOn: [
    acrPull
  ]
}

module frontendDev 'modules/container-app.bicep' = {
  name: 'ca-frontend-dev'
  params: {
    name: frontendDevName
    location: location
    environmentId: environment.id
    identityId: pullIdentity.id
    registryLoginServer: registry.properties.loginServer
    deployStamp: deployStamp
    image: '${registry.properties.loginServer}/${frontendRepository}:${devTag}'
    containerName: 'frontend'
    targetPort: 80
    probePath: '/'
    maxReplicas: maxReplicas
    tags: union(projectTag, { environment: 'DEV' })
    containerEnv: [
      { name: 'BACKEND_URL', value: backendDev.outputs.url }
    ]
  }
  dependsOn: [
    acrPull
  ]
}

module backendProd 'modules/container-app.bicep' = {
  name: 'ca-backend-prod'
  params: {
    name: backendProdName
    location: location
    environmentId: environment.id
    identityId: pullIdentity.id
    registryLoginServer: registry.properties.loginServer
    deployStamp: deployStamp
    image: '${registry.properties.loginServer}/${backendRepository}:${prodTag}'
    containerName: 'backend'
    targetPort: 8000
    probePath: '/api/health'
    maxReplicas: maxReplicas
    tags: union(projectTag, { environment: 'PROD' })
    containerEnv: [
      { name: 'APP_ENV', value: 'PROD' }
      { name: 'APP_VERSION', value: prodTag }
    ]
  }
  dependsOn: [
    acrPull
  ]
}

module frontendProd 'modules/container-app.bicep' = {
  name: 'ca-frontend-prod'
  params: {
    name: frontendProdName
    location: location
    environmentId: environment.id
    identityId: pullIdentity.id
    registryLoginServer: registry.properties.loginServer
    deployStamp: deployStamp
    image: '${registry.properties.loginServer}/${frontendRepository}:${prodTag}'
    containerName: 'frontend'
    targetPort: 80
    probePath: '/'
    maxReplicas: maxReplicas
    tags: union(projectTag, { environment: 'PROD' })
    containerEnv: [
      { name: 'BACKEND_URL', value: backendProd.outputs.url }
    ]
  }
  dependsOn: [
    acrPull
  ]
}

output acrName string = registry.name
output acrLoginServer string = registry.properties.loginServer
output pullIdentityId string = pullIdentity.id
output pullIdentityPrincipalId string = pullIdentity.properties.principalId
output environmentName string = environment.name
output backendRepository string = backendRepository
output frontendRepository string = frontendRepository
output backendDevName string = backendDevName
output frontendDevName string = frontendDevName
output backendProdName string = backendProdName
output frontendProdName string = frontendProdName
output backendDevUrl string = backendDev.outputs.url
output frontendDevUrl string = frontendDev.outputs.url
output backendProdUrl string = backendProd.outputs.url
output frontendProdUrl string = frontendProd.outputs.url
