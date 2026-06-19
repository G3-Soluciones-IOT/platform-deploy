$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..")
$ComposeFile = Join-Path $RootDir "docker/docker-compose.local.yml"
$EnvFile = Join-Path $RootDir "env/local.env"
$NetworkName = "jameofit-network"

$ComposeArgs = @("compose", "--env-file", $EnvFile, "-f", $ComposeFile)

$RequiredImages = @(
  "config-service:local",
  "eureka-service:local",
  "gateway-service:local",
  "iam-service:local",
  "goals-service:local",
  "meal-plans-service:local",
  "profiles-service:local",
  "recipes-service:local",
  "tracking-service:local",
  "communication-service:local"
)

$DbServices = @(
  "iam-service-postgres",
  "goals-service-postgres",
  "meal-plans-service-postgres",
  "profiles-service-postgres",
  "recipes-service-postgres",
  "tracking-service-postgres",
  "communication-service-mongodb"
)

$DomainServices = @(
  "goals-service",
  "meal-plans-service",
  "profiles-service",
  "recipes-service",
  "tracking-service",
  "communication-service"
)

$ContainersToRemove = @(
  "config-service",
  "eureka-service",
  "gateway-service",
  "iam-service",
  "goals-service",
  "meal-plans-service",
  "profiles-service",
  "recipes-service",
  "tracking-service",
  "communication-service",
  "iam-service-postgres",
  "goals-service-postgres",
  "meal-plans-service-postgres",
  "profiles-service-postgres",
  "recipes-service-postgres",
  "tracking-service-postgres",
  "communication-service-mongodb"
)

function Write-Log {
  param([string]$Message)
  Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message"
}

function Fail {
  param([string]$Message)
  throw "ERROR: $Message"
}

function Require-Command {
  param([string]$CommandName)

  if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
    Fail "Command not found: $CommandName"
  }
}

function Require-File {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    Fail "Required file not found: $Path"
  }
}

function Require-Images {
  Write-Log "Validating local Docker images..."

  foreach ($Image in $RequiredImages) {
    docker image inspect $Image *> $null

    if ($LASTEXITCODE -ne 0) {
      Fail "Missing Docker image: $Image. Build it before running local-up.ps1."
    }
  }
}

function Ensure-Network {
  docker network inspect $NetworkName *> $null

  if ($LASTEXITCODE -eq 0) {
    Write-Log "Docker network already exists: $NetworkName"
  }
  else {
    Write-Log "Creating Docker network: $NetworkName"
    docker network create $NetworkName *> $null
  }
}

function Remove-PreviousContainers {
  Write-Log "Removing previous local containers if they exist..."

  foreach ($Container in $ContainersToRemove) {
    docker rm -f $Container *> $null
  }
}

function Wait-Http {
  param(
    [string]$Name,
    [string]$Url,
    [int]$MaxAttempts = 60,
    [int]$SleepSeconds = 2
  )

  Write-Log "Waiting for $Name`: $Url"

  for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
    try {
      if ($PSVersionTable.PSVersion.Major -lt 6) {
        Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5 *> $null
      }
      else {
        Invoke-WebRequest -Uri $Url -TimeoutSec 5 *> $null
      }

      Write-Log "$Name is ready"
      return
    }
    catch {
      Start-Sleep -Seconds $SleepSeconds
    }
  }

  Fail "$Name did not become ready: $Url"
}

function Wait-ContainerReady {
  param(
    [string]$Container,
    [int]$MaxAttempts = 60,
    [int]$SleepSeconds = 2
  )

  Write-Log "Waiting for container: $Container"

  for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
    $Status = docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' $Container 2>$null

    if ($Status -eq "healthy" -or $Status -eq "running") {
      Write-Log "$Container is $Status"
      return
    }

    Start-Sleep -Seconds $SleepSeconds
  }

  Fail "Container did not become ready: $Container"
}

function Wait-EurekaApp {
  param(
    [string]$AppName,
    [int]$MaxAttempts = 60,
    [int]$SleepSeconds = 2
  )

  $Url = "http://localhost:8761/eureka/apps/$AppName"
  Write-Log "Waiting for Eureka registration: $AppName"

  for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
    try {
      if ($PSVersionTable.PSVersion.Major -lt 6) {
        $Response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
      }
      else {
        $Response = Invoke-WebRequest -Uri $Url -TimeoutSec 5
      }

      if ($Response.Content -match "<status>UP</status>") {
        Write-Log "$AppName is registered in Eureka"
        return
      }
    }
    catch {
      Start-Sleep -Seconds $SleepSeconds
    }
  }

  Fail "$AppName did not register as UP in Eureka"
}

Require-Command "docker"
Require-File $ComposeFile
Require-File $EnvFile

Require-Images
Ensure-Network
Remove-PreviousContainers

Write-Log "Starting databases..."
& docker @ComposeArgs up -d @DbServices

foreach ($DbService in $DbServices) {
  Wait-ContainerReady $DbService
}

Write-Log "Starting config-service..."
& docker @ComposeArgs up -d config-service
Wait-Http "config-service" "http://localhost:8888/actuator/health"

Write-Log "Starting eureka-service..."
& docker @ComposeArgs up -d eureka-service
Wait-Http "eureka-service" "http://localhost:8761/actuator/health"

Write-Log "Starting iam-service..."
& docker @ComposeArgs up -d iam-service
Wait-Http "iam-service" "http://localhost:8081/actuator/health"
Wait-EurekaApp "IAM-SERVICE"

Write-Log "Starting domain services..."
& docker @ComposeArgs up -d @DomainServices

Wait-Http "goals-service" "http://localhost:8083/actuator/health"
Wait-Http "meal-plans-service" "http://localhost:8084/actuator/health"
Wait-Http "profiles-service" "http://localhost:8086/actuator/health"
Wait-Http "recipes-service" "http://localhost:8087/actuator/health"
Wait-Http "tracking-service" "http://localhost:8089/actuator/health"
Wait-Http "communication-service" "http://localhost:8090/actuator/health"

Wait-EurekaApp "GOALS-SERVICE"
Wait-EurekaApp "MEAL-PLANS-SERVICE"
Wait-EurekaApp "PROFILES-SERVICE"
Wait-EurekaApp "RECIPES-SERVICE"
Wait-EurekaApp "TRACKING-SERVICE"
Wait-EurekaApp "COMMUNICATION-SERVICE"

Write-Log "Starting gateway-service..."
& docker @ComposeArgs up -d gateway-service
Wait-Http "gateway-service" "http://localhost:8080/actuator/health"
Wait-EurekaApp "GATEWAY-SERVICE"

Write-Log "Local platform is up."
Write-Log "Eureka dashboard: http://localhost:8761"
Write-Log "Gateway: http://localhost:8080"
