#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker/docker-compose.local.yml"
ENV_FILE="${ROOT_DIR}/env/local.env"
NETWORK_NAME="jameofit-network"

COMPOSE=(docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")

REQUIRED_IMAGES=(
  "config-service:local"
  "eureka-service:local"
  "gateway-service:local"
  "iam-service:local"
  "goals-service:local"
  "meal-plans-service:local"
  "payments-service:local"
  "profiles-service:local"
  "recipes-service:local"
  "tracking-service:local"
  "communication-service:local"
)

DB_SERVICES=(
  "iam-service-postgres"
  "goals-service-postgres"
  "meal-plans-service-postgres"
  "payments-service-postgres"
  "profiles-service-postgres"
  "recipes-service-postgres"
  "tracking-service-postgres"
  "communication-service-mongodb"
)

DOMAIN_SERVICES=(
  "goals-service"
  "meal-plans-service"
  "payments-service"
  "profiles-service"
  "recipes-service"
  "tracking-service"
  "communication-service"
)

CONTAINERS_TO_REMOVE=(
  "config-service"
  "eureka-service"
  "gateway-service"
  "iam-service"
  "goals-service"
  "meal-plans-service"
  "payments-service"
  "profiles-service"
  "recipes-service"
  "tracking-service"
  "communication-service"
  "iam-service-postgres"
  "goals-service-postgres"
  "meal-plans-service-postgres"
  "payments-service-postgres"
  "profiles-service-postgres"
  "recipes-service-postgres"
  "tracking-service-postgres"
  "communication-service-mongodb"
)

log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_file() {
  local file="$1"
  [[ -f "${file}" ]] || fail "Required file not found: ${file}"
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 || fail "Command not found: ${command_name}"
}

require_images() {
  log "Validating local Docker images..."

  for image in "${REQUIRED_IMAGES[@]}"; do
    if ! docker image inspect "${image}" >/dev/null 2>&1; then
      fail "Missing Docker image: ${image}. Build it before running local-up.sh."
    fi
  done
}

ensure_network() {
  if docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
    log "Docker network already exists: ${NETWORK_NAME}"
  else
    log "Creating Docker network: ${NETWORK_NAME}"
    docker network create "${NETWORK_NAME}" >/dev/null
  fi
}

remove_previous_containers() {
  log "Removing previous local containers if they exist..."

  for container in "${CONTAINERS_TO_REMOVE[@]}"; do
    docker rm -f "${container}" >/dev/null 2>&1 || true
  done
}

wait_http() {
  local name="$1"
  local url="$2"
  local max_attempts="${3:-60}"
  local sleep_seconds="${4:-2}"

  log "Waiting for ${name}: ${url}"

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      log "${name} is ready"
      return 0
    fi

    sleep "${sleep_seconds}"
  done

  fail "${name} did not become ready: ${url}"
}

wait_container_healthy() {
  local container="$1"
  local max_attempts="${2:-60}"
  local sleep_seconds="${3:-2}"

  log "Waiting for healthy container: ${container}"

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    local status
    status="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${container}" 2>/dev/null || true)"

    if [[ "${status}" == "healthy" || "${status}" == "running" ]]; then
      log "${container} is ${status}"
      return 0
    fi

    sleep "${sleep_seconds}"
  done

  fail "Container did not become healthy/running: ${container}"
}

wait_eureka_app() {
  local app_name="$1"
  local max_attempts="${2:-60}"
  local sleep_seconds="${3:-2}"
  local url="http://localhost:8761/eureka/apps/${app_name}"

  log "Waiting for Eureka registration: ${app_name}"

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if curl -fsS "${url}" | grep -q "<status>UP</status>"; then
      log "${app_name} is registered in Eureka"
      return 0
    fi

    sleep "${sleep_seconds}"
  done

  fail "${app_name} did not register as UP in Eureka"
}

main() {
  require_command docker
  require_command curl
  require_file "${COMPOSE_FILE}"
  require_file "${ENV_FILE}"

  require_images
  ensure_network
  remove_previous_containers

  log "Starting databases..."
  "${COMPOSE[@]}" up -d "${DB_SERVICES[@]}"

  for db_service in "${DB_SERVICES[@]}"; do
    wait_container_healthy "${db_service}"
  done

  log "Starting config-service..."
  "${COMPOSE[@]}" up -d config-service
  wait_http "config-service" "http://localhost:8888/actuator/health"

  log "Starting eureka-service..."
  "${COMPOSE[@]}" up -d eureka-service
  wait_http "eureka-service" "http://localhost:8761/actuator/health"

  log "Starting iam-service..."
  "${COMPOSE[@]}" up -d iam-service
  wait_http "iam-service" "http://localhost:8081/actuator/health"
  wait_eureka_app "IAM-SERVICE"

  log "Starting domain services..."
  "${COMPOSE[@]}" up -d "${DOMAIN_SERVICES[@]}"

  wait_http "goals-service" "http://localhost:8083/actuator/health"
  wait_http "meal-plans-service" "http://localhost:8084/actuator/health"
  wait_http "payments-service" "http://localhost:8092/actuator/health"
  wait_http "profiles-service" "http://localhost:8086/actuator/health"
  wait_http "recipes-service" "http://localhost:8087/actuator/health"
  wait_http "tracking-service" "http://localhost:8089/actuator/health"
  wait_http "communication-service" "http://localhost:8090/actuator/health"

  wait_eureka_app "GOALS-SERVICE"
  wait_eureka_app "MEAL-PLANS-SERVICE"
  wait_eureka_app "PAYMENTS-SERVICE"
  wait_eureka_app "PROFILES-SERVICE"
  wait_eureka_app "RECIPES-SERVICE"
  wait_eureka_app "TRACKING-SERVICE"
  wait_eureka_app "COMMUNICATION-SERVICE"

  log "Starting gateway-service..."
  "${COMPOSE[@]}" up -d gateway-service
  wait_http "gateway-service" "http://localhost:8080/actuator/health"
  wait_eureka_app "GATEWAY-SERVICE"

  log "Local platform is up."
  log "Eureka dashboard: http://localhost:8761"
  log "Gateway: http://localhost:8080"
}

main "$@"
