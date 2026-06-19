$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..")
$ComposeFile = Join-Path $RootDir "docker/docker-compose.local.yml"
$EnvFile = Join-Path $RootDir "env/local.env"

$ComposeArgs = @("compose", "--env-file", $EnvFile, "-f", $ComposeFile)

$RemoveVolumes = $env:REMOVE_VOLUMES

if (-not (Test-Path $EnvFile)) {
  Write-Host "WARN: $EnvFile not found. Compose may fail."
}

Write-Host "Stopping JameoFit local platform..."

if ($RemoveVolumes -eq "true") {
  Write-Host "Stopping containers and removing volumes..."
  & docker @ComposeArgs down -v --remove-orphans
}
else {
  Write-Host "Stopping containers without removing volumes..."
  & docker @ComposeArgs down --remove-orphans
}

Write-Host "Done."