#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/env/gcp.env"
COMPOSE_FILE="${ROOT_DIR}/docker/docker-compose.gcp.yml"
COMPOSE=(docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/gcp-services.sh"

EUREKA_APP_MAX_ATTEMPTS=150
EUREKA_APP_SLEEP_SECONDS=2
EUREKA_APP_PROGRESS_INTERVAL_ATTEMPTS="${EUREKA_APP_PROGRESS_INTERVAL_ATTEMPTS:-10}"

if [ ! -f "${ENV_FILE}" ]; then
  echo "[ERROR] ${ENV_FILE} not found."
  echo "Run scripts/gcp-load-secrets.sh first."
  exit 1
fi

read_env_value() {
  local variable_name="$1"
  local value

  value="$(grep -m 1 "^${variable_name}=" "${ENV_FILE}" | cut -d '=' -f 2- || true)"
  if [[ -z "${value}" ]]; then
    fail "${variable_name} is required in ${ENV_FILE}"
  fi

  echo "${value}"
}

read_optional_env_value() {
  local variable_name="$1"
  grep -m 1 "^${variable_name}=" "${ENV_FILE}" | cut -d '=' -f 2- || true
}

log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

fail() {
  echo "[ERROR] $*" >&2
  exit 1
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 || fail "Command not found: ${command_name}"
}

validate_image_tag() {
  local variable_name="$1"
  local value

  value="$(grep -m 1 "^${variable_name}=" "${ENV_FILE}" | cut -d '=' -f 2- || true)"
  if [[ ! "${value}" =~ ^sha-[0-9a-f]{7}$ ]]; then
    echo "[ERROR] ${variable_name} in ${ENV_FILE} must use the immutable sha-<7-hex-character> format."
    exit 1
  fi
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

wait_eureka_app() {
  local app_name="$1"
  local max_attempts="${2:-60}"
  local sleep_seconds="${3:-2}"

  wait_eureka_apps "${app_name}" "${max_attempts}" "${sleep_seconds}" "${app_name}"
}

eureka_app_is_up() {
  local app_name="$1"
  local url="http://127.0.0.1:${EUREKA_SERVICE_PORT}/eureka/apps/${app_name}"

  curl -fsS "${url}" 2>/dev/null | grep -q "<status>UP</status>"
}

eureka_app_service_name() {
  local app_name="$1"

  echo "${app_name}" | tr '[:upper:]' '[:lower:]'
}

container_state_summary() {
  local service_name="$1"
  local container_id
  local inspect_output

  container_id="$("${COMPOSE[@]}" ps -q "${service_name}" 2>/dev/null || true)"
  if [[ -z "${container_id}" ]]; then
    echo "container=missing"
    return 0
  fi

  inspect_output="$(docker inspect \
    --format 'status={{.State.Status}} exit={{.State.ExitCode}} restarting={{.State.Restarting}} restarts={{.RestartCount}}' \
    "${container_id}" 2>/dev/null || true)"

  if [[ -z "${inspect_output}" ]]; then
    echo "container=${container_id} state=unknown"
    return 0
  fi

  echo "${inspect_output}"
}

print_service_diagnostics() {
  local service_name="$1"

  log "Container status for ${service_name}:"
  "${COMPOSE[@]}" ps "${service_name}" || true
  log "Recent logs for ${service_name}:"
  "${COMPOSE[@]}" logs --tail=200 "${service_name}" || true
}

fail_if_container_stopped() {
  local app_name="$1"
  local service_name
  local summary

  service_name="$(eureka_app_service_name "${app_name}")"
  summary="$(container_state_summary "${service_name}")"

  if [[ "${summary}" == *"status=exited"* ||
        "${summary}" == *"status=dead"* ||
        "${summary}" == *"status=restarting"* ||
        "${summary}" == *"restarting=true"* ]]; then
    log "${app_name} cannot register because ${service_name} is not stable (${summary})."
    print_service_diagnostics "${service_name}"
    fail "${app_name} did not register as UP in Eureka"
  fi
}

wait_eureka_apps() {
  local label="$1"
  local max_attempts="$2"
  local sleep_seconds="$3"
  shift 3
  local pending=("$@")
  local next_pending=()
  local app_name
  local service_name
  local summary
  local pending_names

  if (( ${#pending[@]} == 0 )); then
    return 0
  fi

  log "Waiting for Eureka registration: ${label}"

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    next_pending=()

    for app_name in "${pending[@]}"; do
      if eureka_app_is_up "${app_name}"; then
        log "${app_name} is registered in Eureka"
        continue
      fi

      fail_if_container_stopped "${app_name}"
      next_pending+=("${app_name}")
    done

    pending=("${next_pending[@]}")
    if (( ${#pending[@]} == 0 )); then
      return 0
    fi

    if (( attempt == 1 || attempt % EUREKA_APP_PROGRESS_INTERVAL_ATTEMPTS == 0 )); then
      pending_names="$(printf '%s ' "${pending[@]}")"
      log "Still waiting for Eureka (${attempt}/${max_attempts}): ${pending_names}"

      for app_name in "${pending[@]}"; do
        service_name="$(eureka_app_service_name "${app_name}")"
        summary="$(container_state_summary "${service_name}")"
        log "  ${service_name}: ${summary}"
      done
    fi

    sleep "${sleep_seconds}"
  done

  for app_name in "${pending[@]}"; do
    service_name="$(eureka_app_service_name "${app_name}")"
    print_service_diagnostics "${service_name}"
  done

  fail "${label} did not register as UP in Eureka"
}

wait_config_property() {
  local service_name="$1"
  local profile="$2"
  local property_name="$3"
  local max_attempts="${4:-60}"
  local sleep_seconds="${5:-2}"
  local url="http://127.0.0.1:${CONFIG_SERVICE_PORT}/${service_name}/${profile}"

  log "Waiting for Config Server property: ${service_name}/${profile} -> ${property_name}"

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if curl -fsS "${url}" 2>/dev/null | grep -q "\"${property_name}\""; then
      log "Config Server is serving ${property_name}"
      return 0
    fi

    sleep "${sleep_seconds}"
  done

  fail "Config Server did not serve required property ${property_name} from ${url}"
}

compose_up() {
  "${COMPOSE[@]}" up -d --force-recreate --no-deps "$@"
}

main() {
  require_command gcloud
  require_command docker
  require_command curl
  require_command grep

  CONFIG_SERVICE_PORT="$(read_env_value CONFIG_SERVICE_PORT)"
  EUREKA_SERVICE_PORT="$(read_env_value EUREKA_SERVICE_PORT)"
  GATEWAY_SERVICE_PORT="$(read_env_value GATEWAY_SERVICE_PORT)"
  SPRING_PROFILES_ACTIVE="$(read_env_value SPRING_PROFILES_ACTIVE)"
  GCP_REGION="$(read_env_value GCP_REGION)"
  ACTIVE_COMPOSE_PROFILES="${COMPOSE_PROFILES:-$(read_optional_env_value COMPOSE_PROFILES)}"

  mapfile -t REQUIRED_IMAGE_TAGS < <(gcp_service_image_tag_vars "${ACTIVE_COMPOSE_PROFILES}")
  mapfile -t REQUIRED_RUNTIME_VARS < <(gcp_service_runtime_vars "${ACTIVE_COMPOSE_PROFILES}")
  mapfile -t DOMAIN_SERVICES < <(gcp_service_names_by_group "domain" "${ACTIVE_COMPOSE_PROFILES}")
  mapfile -t DOMAIN_EUREKA_APPS < <(gcp_service_eureka_apps_by_group "domain" "${ACTIVE_COMPOSE_PROFILES}")
  mapfile -t OPENAPI_HTTP_SERVICES < <(gcp_service_openapi_names "${ACTIVE_COMPOSE_PROFILES}")

  for variable_name in "${REQUIRED_IMAGE_TAGS[@]}"; do
    validate_image_tag "${variable_name}"
  done

  for variable_name in "${REQUIRED_RUNTIME_VARS[@]}"; do
    read_env_value "${variable_name}" >/dev/null
  done

  if [[ ",${ACTIVE_COMPOSE_PROFILES}," == *,communication,* ]]; then
    if ! grep -q '^COMMUNICATION_MONGODB_URI=' "${ENV_FILE}"; then
      echo "[ERROR] communication profile requires COMMUNICATION_MONGODB_SECRET_ID when running gcp-load-secrets.sh."
      exit 1
    fi
  fi

  log "Authenticating Docker with Artifact Registry..."
  gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --quiet

  log "Pulling images..."
  "${COMPOSE[@]}" pull

  log "Starting config-service..."
  compose_up config-service
  wait_http "config-service" "http://127.0.0.1:${CONFIG_SERVICE_PORT}/actuator/health"
  wait_config_property \
    "iam-service" \
    "${SPRING_PROFILES_ACTIVE}" \
    "spring.jpa.hibernate.naming.physical-strategy"
  wait_config_property \
    "gateway-service" \
    "${SPRING_PROFILES_ACTIVE}" \
    "spring.security.oauth2.resource-server.jwt.issuer-uri"
  wait_config_property \
    "gateway-service" \
    "${SPRING_PROFILES_ACTIVE}" \
    "auth0.audience"
  wait_config_property \
    "gateway-service" \
    "${SPRING_PROFILES_ACTIVE}" \
    "legacy.jwt.enabled"

  for service_name in "${OPENAPI_HTTP_SERVICES[@]}"; do
    wait_config_property \
      "${service_name}" \
      "${SPRING_PROFILES_ACTIVE}" \
      "documentation.openapi.server-url"
  done

  log "Starting eureka-service..."
  compose_up eureka-service
  wait_http "eureka-service" "http://127.0.0.1:${EUREKA_SERVICE_PORT}/actuator/health"

  log "Starting iam-service..."
  compose_up iam-service
  wait_eureka_app "IAM-SERVICE" "${EUREKA_APP_MAX_ATTEMPTS}" "${EUREKA_APP_SLEEP_SECONDS}"

  log "Starting domain services..."
  compose_up "${DOMAIN_SERVICES[@]}"

  wait_eureka_apps \
    "domain services" \
    "${EUREKA_APP_MAX_ATTEMPTS}" \
    "${EUREKA_APP_SLEEP_SECONDS}" \
    "${DOMAIN_EUREKA_APPS[@]}"

  log "Starting gateway-service..."
  compose_up gateway-service
  wait_http "gateway-service" "http://127.0.0.1:${GATEWAY_SERVICE_PORT}/actuator/health"
  wait_eureka_app "GATEWAY-SERVICE" "${EUREKA_APP_MAX_ATTEMPTS}" "${EUREKA_APP_SLEEP_SECONDS}"

  log "Containers:"
  "${COMPOSE[@]}" ps

  log "JameoFit GCP platform is up."
}

main "$@"
