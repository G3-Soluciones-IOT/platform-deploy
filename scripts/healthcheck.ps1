$ErrorActionPreference = "Stop"

function Check-Http {
  param(
    [string]$Name,
    [string]$Url
  )

  Write-Host ("Checking {0,-28} {1} ... " -f $Name, $Url) -NoNewline

  try {
    if ($PSVersionTable.PSVersion.Major -lt 6) {
      Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5 *> $null
    }
    else {
      Invoke-WebRequest -Uri $Url -TimeoutSec 5 *> $null
    }

    Write-Host "OK"
  }
  catch {
    Write-Host "FAIL"
    throw
  }
}

function Check-EurekaApp {
  param([string]$AppName)

  $Url = "http://localhost:8761/eureka/apps/$AppName"

  Write-Host ("Checking Eureka app {0,-18} ... " -f $AppName) -NoNewline

  try {
    if ($PSVersionTable.PSVersion.Major -lt 6) {
      $Response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
    }
    else {
      $Response = Invoke-WebRequest -Uri $Url -TimeoutSec 5
    }

    if ($Response.Content -match "<status>UP</status>") {
      Write-Host "OK"
    }
    else {
      Write-Host "FAIL"
      throw "Eureka app is not UP: $AppName"
    }
  }
  catch {
    Write-Host "FAIL"
    throw
  }
}

Write-Host "Checking JameoFit local platform..."
Write-Host ""

Check-Http "config-service" "http://localhost:8888/actuator/health"
Check-Http "eureka-service" "http://localhost:8761/actuator/health"
Check-Http "iam-service" "http://localhost:8081/actuator/health"
Check-Http "goals-service" "http://localhost:8083/actuator/health"
Check-Http "meal-plans-service" "http://localhost:8084/actuator/health"
Check-Http "payments-service" "http://localhost:8092/actuator/health"
Check-Http "nutritionist-service" "http://localhost:8085/actuator/health"
Check-Http "profiles-service" "http://localhost:8086/actuator/health"
Check-Http "recipes-service" "http://localhost:8087/actuator/health"
Check-Http "tracking-service" "http://localhost:8089/actuator/health"
Check-Http "communication-service" "http://localhost:8090/actuator/health"
Check-Http "gateway-service" "http://localhost:8080/actuator/health"

Write-Host ""
Write-Host "Checking Eureka registrations..."
Write-Host ""

Check-EurekaApp "IAM-SERVICE"
Check-EurekaApp "GOALS-SERVICE"
Check-EurekaApp "MEAL-PLANS-SERVICE"
Check-EurekaApp "PAYMENTS-SERVICE"
Check-EurekaApp "NUTRITIONIST-SERVICE"
Check-EurekaApp "PROFILES-SERVICE"
Check-EurekaApp "RECIPES-SERVICE"
Check-EurekaApp "TRACKING-SERVICE"
Check-EurekaApp "COMMUNICATION-SERVICE"
Check-EurekaApp "GATEWAY-SERVICE"

Write-Host ""
Write-Host "All local healthchecks passed."
