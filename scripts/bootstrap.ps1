#Requires -Version 5.1
<#
.SYNOPSIS
  Creates the SINWO Azure footprint and the GitHub dev and prod environments.

.DESCRIPTION
  Deploys infra/main.bicep into rg-sinwo-cicd in two passes: shared resources
  first, then the four Container Apps once the *-latest image tags exist. It
  seeds those tags on the first run, then stores the GitHub environment
  variables and OIDC identifiers the workflows use. No password or secret is
  stored in GitHub: the registry admin user is disabled, Container Apps pull
  with a managed identity, and GitHub Actions signs in through a federated
  credential. Rerunning resets each app to its *-latest image tag and
  APP_VERSION=*-latest. Those tags still point at the last pushed image.

.PARAMETER ResourceGroupName
  Resource group to create or update. Default: rg-sinwo-cicd.

.PARAMETER Location
  Region used when the resource group is created. Default: germanywestcentral.
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
    [string]$Location = "germanywestcentral",
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

function Invoke-Quiet {
    param([Parameter(Mandatory = $true)][scriptblock]$Command)

    # Windows PowerShell 5 turns native stderr into a terminating error under "Stop".
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Command 2>$null
    }
    finally {
        $ErrorActionPreference = $previous
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
    $repoIds = gh api "repos/$GitHubRepo" --jq "{ownerId: .owner.id, repoId: .id}" | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $repoIds.ownerId -or -not $repoIds.repoId) {
        throw "Could not read the GitHub owner id and repository id for '$GitHubRepo'."
    }
    Write-Host "GitHub OIDC subject ids: owner $($repoIds.ownerId), repository $($repoIds.repoId)"

    Write-Host "Registering resource providers..."
    Invoke-Checked { az provider register --namespace Microsoft.App --wait } "Failed to register Microsoft.App."
    Invoke-Checked { az provider register --namespace Microsoft.OperationalInsights --wait } "Failed to register Microsoft.OperationalInsights."
    Invoke-Checked { az provider register --namespace Microsoft.ContainerRegistry --wait } "Failed to register Microsoft.ContainerRegistry."
    Invoke-Checked { az provider register --namespace Microsoft.ManagedIdentity --wait } "Failed to register Microsoft.ManagedIdentity."

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
            $previousAcr = Invoke-Quiet { az deployment group show --resource-group $ResourceGroupName --name sinwo-infra --query properties.outputs.acrName.value --output tsv }
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

    $deployStamp = Get-Date -Format "yyyyMMddHHmmss"
    function Invoke-InfraDeployment {
        param([bool]$DeployApps)

        $deployArgs = @(
            "deployment", "group", "create",
            "--name", "sinwo-infra",
            "--resource-group", $ResourceGroupName,
            "--template-file", $template,
            "--parameters", "location=$Location", "acrName=$AcrName", "githubRepo=$GitHubRepo", "githubOwnerId=$($repoIds.ownerId)", "githubRepositoryId=$($repoIds.repoId)",
            "deployStamp=$deployStamp", "deployApps=$($DeployApps.ToString().ToLower())",
            "--query", "properties.outputs",
            "--output", "json"
        )
        $json = az @deployArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Deployment failed. Retrying once in case a new identity has not replicated yet..."
            Start-Sleep -Seconds 30
            $json = az @deployArgs
            if ($LASTEXITCODE -ne 0) {
                throw "Bicep deployment failed."
            }
        }
        return ($json | ConvertFrom-Json)
    }

    Write-Host "Deploying shared infrastructure (registry $AcrName, region $Location)..."
    $outputs = Invoke-InfraDeployment -DeployApps $false
    $resolvedAcrName = $outputs.acrName.value
    $loginServer = $outputs.acrLoginServer.value

    Write-Host "Configuring registry access for managed identity pull..."
    Invoke-Checked { az acr update --name $resolvedAcrName --role-assignment-mode rbac --output none } "Could not set the registry role assignment mode to rbac."
    Invoke-Checked { az acr config authentication-as-arm update --registry $resolvedAcrName --status enabled --output none } "Could not enable ARM audience tokens on the registry. Managed identity image pull needs that policy."

    foreach ($image in @(
            @{ Repository = $outputs.backendRepository.value; Context = "backend" },
            @{ Repository = $outputs.frontendRepository.value; Context = "frontend" }
        )) {
        $tags = Invoke-Quiet { az acr repository show-tags --name $resolvedAcrName --repository $image.Repository --output tsv }
        if ($LASTEXITCODE -eq 0 -and $tags -contains "dev-latest" -and $tags -contains "prod-latest") {
            continue
        }

        Write-Host "Seeding $($image.Repository):dev-latest and :prod-latest so the apps have an image to start..."
        $useDocker = $false
        if (Get-Command docker -ErrorAction SilentlyContinue) {
            Invoke-Quiet { docker info --format "{{.ServerVersion}}" } | Out-Null
            $useDocker = ($LASTEXITCODE -eq 0)
        }

        if ($useDocker) {
            Invoke-Checked { az acr login --name $resolvedAcrName } "Could not sign in to $resolvedAcrName with your Azure account."
            Invoke-Checked {
                docker buildx build --platform linux/amd64 --provenance=false --sbom=false --target prod `
                    -t "$loginServer/$($image.Repository):dev-latest" -t "$loginServer/$($image.Repository):prod-latest" `
                    --push $image.Context
            } "Docker build of $($image.Context) failed."
        }
        else {
            Write-Host "Docker is not running. Building in the registry with az acr build instead."
            Invoke-Checked {
                az acr build --registry $resolvedAcrName --platform linux/amd64 --target prod `
                    --image "$($image.Repository):dev-latest" --image "$($image.Repository):prod-latest" `
                    $image.Context
            } "az acr build of $($image.Context) failed. Start Docker Desktop and rerun the script."
        }
    }

    Write-Host "Deploying the four Container Apps..."
    $outputs = Invoke-InfraDeployment -DeployApps $true

    Write-Host "Removing registry passwords from GitHub..."
    foreach ($secret in "ACR_USERNAME", "ACR_PASSWORD") {
        Invoke-Quiet { gh secret delete $secret --repo $GitHubRepo } | Out-Null
    }

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
    Set-RepoVariable "AZURE_CLIENT_ID" $outputs.deployIdentityClientId.value
    Set-RepoVariable "AZURE_TENANT_ID" $outputs.tenantId.value
    Set-RepoVariable "AZURE_SUBSCRIPTION_ID" $account.id

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

    Write-Host "Configuring branch protection on main..."
    $protection = @{
        required_status_checks        = @{
            strict   = $true
            contexts = @("ci-status")
        }
        enforce_admins                = $false
        required_pull_request_reviews = $null
        restrictions                  = $null
    } | ConvertTo-Json -Depth 5 -Compress
    $protection | gh api --method PUT "repos/$GitHubRepo/branches/main/protection" --input - --silent
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not require the ci-status check on main. A private repository on the free plan cannot use branch protection."
    }
    else {
        Write-Host "main now requires the ci-status check."
    }

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
    Write-Host "GitHub Actions signs in with the deploy identity through OIDC. No registry password is stored in GitHub."
    Write-Host "This run points each app at its *-latest tag and sets APP_VERSION to that tag. The tag still refers to the last image that was pushed."
    if (-not $ProdReviewer) {
        Write-Host "The prod environment has no required reviewer. Re-run with -ProdReviewer <github-user> to add one."
    }
}
finally {
    Pop-Location
}
