#Requires -Version 5.1
<#
.SYNOPSIS
  Creates the SINWO Azure footprint and the GitHub dev and prod environments.

.DESCRIPTION
  Deploys infra/main.bicep into rg-sinwo-cicd, then stores the ACR admin
  credentials as repository secrets and the per-environment backend URLs as
  GitHub environment variables. Phase 1 uses the ACR admin user because the
  university tenant blocks Entra app registrations. The script does not print
  the registry password.

.PARAMETER ResourceGroupName
  Resource group to create or update. Default: rg-sinwo-cicd.

.PARAMETER Location
  Region used when the resource group is created. Default: westeurope.
  An existing group keeps its current region.

.PARAMETER AcrName
  Optional globally unique registry name. Omit it to generate a name that
  stays the same for this resource group and subscription.

.PARAMETER Subscription
  Optional subscription name or ID. Uses the current Azure CLI account when omitted.

.PARAMETER GitHubRepo
  owner/name repository. Defaults to the GitHub repo of this checkout.

.PARAMETER ProdReviewer
  Optional GitHub username required to approve production deployments.

.EXAMPLE
  ./scripts/bootstrap.ps1

.EXAMPLE
  ./scripts/bootstrap.ps1 -AcrName acrsinwocicd01 -ProdReviewer octocat
#>
[CmdletBinding()]
param(
    [string]$ResourceGroupName = "rg-sinwo-cicd",
    [string]$Location = "westeurope",
    [string]$AcrName,
    [string]$Subscription,
    [string]$GitHubRepo,
    [string]$ProdReviewer
)

$ErrorActionPreference = "Stop"

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command,
        [Parameter(Mandatory = $true)]
        [string]$FailureMessage
    )

    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw $FailureMessage
    }
}

function Test-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' is not on PATH."
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$template = Join-Path $repoRoot "infra\main.bicep"
if (-not (Test-Path $template)) {
    throw "Bicep template not found at $template"
}

Test-Command "az"
Test-Command "gh"

if ($AcrName -and $AcrName -notmatch "^[a-zA-Z0-9]{5,50}$") {
    throw "ACR name must be 5-50 alphanumeric characters."
}

Write-Host "Checking Azure CLI and GitHub CLI sign-in..."
Invoke-Checked { az account show --output none } "Azure CLI is not signed in. Run 'az login' and try again."
Invoke-Checked { gh auth status } "GitHub CLI is not signed in. Run 'gh auth login' and try again."

if ($Subscription) {
    Invoke-Checked { az account set --subscription $Subscription } "Could not select subscription '$Subscription'."
}

$account = az account show --query "{name:name,id:id,user:user.name}" --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw "Could not read the active Azure subscription."
}
Write-Host "Subscription: $($account.name) ($($account.id))"
Write-Host "Signed in as: $($account.user)"

Push-Location $repoRoot
try {
    if (-not $GitHubRepo) {
        $GitHubRepo = gh repo view --json nameWithOwner --jq ".nameWithOwner"
        if ($LASTEXITCODE -ne 0 -or -not $GitHubRepo) {
            throw "Could not detect the GitHub repo. Pass -GitHubRepo owner/name."
        }
    }
    Write-Host "GitHub repository: $GitHubRepo"

    Write-Host "Registering resource providers..."
    Invoke-Checked { az provider register --namespace Microsoft.App --wait } "Failed to register Microsoft.App."
    Invoke-Checked { az provider register --namespace Microsoft.OperationalInsights --wait } "Failed to register Microsoft.OperationalInsights."
    Invoke-Checked { az provider register --namespace Microsoft.ContainerRegistry --wait } "Failed to register Microsoft.ContainerRegistry."

    $existingGroup = (az group exists --name $ResourceGroupName --output tsv).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Could not check whether resource group '$ResourceGroupName' exists."
    }

    if ($existingGroup -eq "true") {
        $groupLocation = (az group show --name $ResourceGroupName --query location --output tsv).Trim()
        if ($LASTEXITCODE -ne 0) {
            throw "Could not read resource group '$ResourceGroupName'."
        }
        if ($groupLocation -ne $Location) {
            Write-Host "Resource group already exists in '$groupLocation'. Using that region instead of '$Location'."
            $Location = $groupLocation
        }
        if (-not $AcrName) {
            $previousAcr = az deployment group show --resource-group $ResourceGroupName --name sinwo-infra --query properties.outputs.acrName.value --output tsv 2>$null
            if ($LASTEXITCODE -eq 0 -and $previousAcr) {
                $AcrName = $previousAcr.Trim()
            }
        }
    }
    else {
        Write-Host "Creating resource group $ResourceGroupName in $Location..."
        Invoke-Checked { az group create --name $ResourceGroupName --location $Location --output none } "Failed to create resource group '$ResourceGroupName'."
        $Location = (az group show --name $ResourceGroupName --query location --output tsv).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $Location) {
            throw "Could not read the region of resource group '$ResourceGroupName'."
        }
    }

    if (-not $AcrName) {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$ResourceGroupName|$($account.id)"))
        }
        finally {
            $sha.Dispose()
        }
        $suffix = ([System.BitConverter]::ToString($bytes)).Replace("-", "").ToLower().Substring(0, 8)
        $AcrName = "acrsinwo$suffix"
    }

    Write-Host "Deploying infra/main.bicep (registry $AcrName, region $Location)..."
    $deployArgs = @(
        "deployment", "group", "create",
        "--name", "sinwo-infra",
        "--resource-group", $ResourceGroupName,
        "--template-file", $template,
        "--parameters", "location=$Location", "acrName=$AcrName",
        "--query", "properties.outputs",
        "--output", "json"
    )
    $deploymentJson = az @deployArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "First deployment failed. Retrying once in case the managed identity was not replicated yet..."
        Start-Sleep -Seconds 20
        $deploymentJson = az @deployArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Bicep deployment failed."
        }
    }

    $outputs = $deploymentJson | ConvertFrom-Json
    $resolvedAcrName = $outputs.acrName.value
    $loginServer = $outputs.acrLoginServer.value

    Write-Host "Configuring registry access for managed identity pull..."
    Invoke-Checked { az acr update --name $resolvedAcrName --role-assignment-mode rbac --output none } "Could not set the registry role assignment mode to rbac."
    Invoke-Checked { az acr config authentication-as-arm update --registry $resolvedAcrName --status enabled --output none } "Could not enable ARM audience tokens on the registry. Managed identity image pull needs that policy."

    Write-Host "Reading ACR admin credentials..."
    $credentials = az acr credential show --name $resolvedAcrName --query "{username:username,password:passwords[0].value}" --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $credentials.password) {
        throw "Could not read ACR admin credentials. Confirm adminUserEnabled is true on $resolvedAcrName."
    }

    Write-Host "Storing repository secrets and variables..."
    gh secret set ACR_USERNAME --repo $GitHubRepo --body $credentials.username
    if ($LASTEXITCODE -ne 0) { throw "Failed to set ACR_USERNAME." }
    gh secret set ACR_PASSWORD --repo $GitHubRepo --body $credentials.password
    if ($LASTEXITCODE -ne 0) { throw "Failed to set ACR_PASSWORD." }
    $credentials = $null

    function Set-RepoVariable {
        param([string]$Name, [string]$Value)
        gh variable set $Name --repo $GitHubRepo --body $Value
        if ($LASTEXITCODE -ne 0) { throw "Failed to set repository variable $Name." }
    }

    function Set-EnvVariable {
        param([string]$Environment, [string]$Name, [string]$Value)
        gh variable set $Name --repo $GitHubRepo --env $Environment --body $Value
        if ($LASTEXITCODE -ne 0) { throw "Failed to set $Environment variable $Name." }
    }

    Set-RepoVariable "ACR_NAME" $resolvedAcrName
    Set-RepoVariable "ACR_LOGIN_SERVER" $loginServer
    Set-RepoVariable "AZURE_RESOURCE_GROUP" $ResourceGroupName
    Set-RepoVariable "AZURE_LOCATION" $Location
    Set-RepoVariable "IMAGE_REPOSITORY_BACKEND" $outputs.backendRepository.value
    Set-RepoVariable "IMAGE_REPOSITORY_FRONTEND" $outputs.frontendRepository.value

    Write-Host "Creating GitHub environments..."
    '{"wait_timer":0}' | gh api --method PUT "repos/$GitHubRepo/environments/dev" --input - --silent
    if ($LASTEXITCODE -ne 0) { throw "Failed to create the dev environment." }

    if ($ProdReviewer) {
        $reviewerId = gh api "users/$ProdReviewer" --jq ".id"
        if ($LASTEXITCODE -ne 0 -or -not $reviewerId) {
            throw "Could not resolve GitHub user '$ProdReviewer'."
        }
        $prodBody = @{
            wait_timer          = 0
            prevent_self_review = $true
            reviewers           = @(
                @{ type = "User"; id = [int64]$reviewerId }
            )
        } | ConvertTo-Json -Depth 4 -Compress
        $prodBody | gh api --method PUT "repos/$GitHubRepo/environments/prod" --input - --silent
        if ($LASTEXITCODE -ne 0) { throw "Failed to create the prod environment with reviewer $ProdReviewer." }
    }
    else {
        '{"wait_timer":0}' | gh api --method PUT "repos/$GitHubRepo/environments/prod" --input - --silent
        if ($LASTEXITCODE -ne 0) { throw "Failed to create the prod environment." }
    }

    Set-EnvVariable "dev" "BACKEND_URL" $outputs.backendDevUrl.value
    Set-EnvVariable "dev" "FRONTEND_URL" $outputs.frontendDevUrl.value
    Set-EnvVariable "dev" "CONTAINER_APP_BACKEND" $outputs.backendDevName.value
    Set-EnvVariable "dev" "CONTAINER_APP_FRONTEND" $outputs.frontendDevName.value

    Set-EnvVariable "prod" "BACKEND_URL" $outputs.backendProdUrl.value
    Set-EnvVariable "prod" "FRONTEND_URL" $outputs.frontendProdUrl.value
    Set-EnvVariable "prod" "CONTAINER_APP_BACKEND" $outputs.backendProdName.value
    Set-EnvVariable "prod" "CONTAINER_APP_FRONTEND" $outputs.frontendProdName.value

    Write-Host ""
    Write-Host "Infrastructure is ready."
    Write-Host "Resource group: $ResourceGroupName ($Location)"
    Write-Host "Registry:       $loginServer"
    Write-Host "DEV frontend:   $($outputs.frontendDevUrl.value)"
    Write-Host "DEV backend:    $($outputs.backendDevUrl.value)"
    Write-Host "PROD frontend:  $($outputs.frontendProdUrl.value)"
    Write-Host "PROD backend:   $($outputs.backendProdUrl.value)"
    Write-Host ""
    Write-Host "ACR Basic is the standing cost. The four apps use minReplicas 0, so they do not bill while idle."
    Write-Host "Revisions stay unhealthy until the first image push, because the registry is still empty."
    if (-not $ProdReviewer) {
        Write-Host "The prod environment has no required reviewer. Re-run with -ProdReviewer <github-user> to add one."
    }
}
finally {
    Pop-Location
}
