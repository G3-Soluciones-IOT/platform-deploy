#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/env/gcp.env"
COMPOSE_FILE="${ROOT_DIR}/docker/docker-compose.gcp.yml"
COMPOSE=(docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/gcp-services.sh"

EUREKA_APP_MAX_ATTEMPTS="${EUREKA_APP_MAX_ATTEMPTS:-150}"
EUREKA_APP_SLEEP_SECONDS="${EUREKA_APP_SLEEP_SECONDS:-2}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/gcp-deploy-service.sh <service-name> [sha-xxxxxxx]

Examples:
  scripts/gcp-deploy-service.sh payments-service
  scripts/gcp-deploy-service.sh payments-service sha-a1b2c3d

When a tag is provided, the script updates env/gcp.env before pulling and
recreating only the selected service.
USAGE
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

validate_image_tag_value() {
  local value="$1"

  [[ "${value}" =~ ^sha-[0-9a-f]{7}$ ]] || fail "Image tag must use sha-<7-hex-character>, got: ${value}"
}

read_env_value() {
  local variable_name="$1"
  local value

  value="$(grep -m 1 "^${variable_name}=" "${ENV_FILE}" | cut -d '=' -f 2- || true)"
  [[ -n "${value}" ]] || fail "${variable_name} is required in ${ENV_FILE}"

  echo "${value}"
}

read_optional_env_value() {
  local variable_name="$1"
  grep -m 1 "^${variable_name}=" "${ENV_FILE}" | cut -d '=' -f 2- || true
}

update_env_value() {
  local variable_name="$1"
  local value="$2"
  local temp_env

  temp_env="$(mktemp "${ENV_FILE}.XXXXXX")"
  awk -v key="${variable_name}" -v value="${value}" '
    BEGIN { updated = 0 }
    index($0, key "=") == 1 {
      print key "=" value
      updated = 1
      next
    }
    { print }
    END {
      if (updated == 0) {
        print key "=" value
      }
    }
  ' "${ENV_FILE}" > "${temp_env}"

  chmod 600 "${temp_env}"
  mv "${temp_env}" "${ENV_FILE}"
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
  local url="http://127.0.0.1:${EUREKA_SERVICE_PORT}/eureka/apps/${app_name}"

  log "Waiting for Eureka registration: ${app_name}"

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if curl -fsS "${url}" 2>/dev/null | grep -q "<status>UP</status>"; then
      log "${app_name} is registered in Eureka"
      return 0
    fi

    sleep "${sleep_seconds}"
  done

  log "Eureka registration failed for ${app_name}. Container status:"
  "${COMPOSE[@]}" ps "${SERVICE_NAME}" || true
  log "Recent logs for ${SERVICE_NAME}:"
  "${COMPOSE[@]}" logs --tail=200 "${SERVICE_NAME}" || true
  fail "${app_name} did not register as UP in Eureka"
}

wait_deployed_service() {
  local service_name="$1"
  local eureka_app="$2"

  case "${service_name}" in
    config-service)
      wait_http "config-service" "http://127.0.0.1:${CONFIG_SERVICE_PORT}/actuator/health"
      ;;
    eureka-service)
      wait_http "eureka-service" "http://127.0.0.1:${EUREKA_SERVICE_PORT}/actuator/health"
      ;;
    gateway-service)
      wait_http "gateway-service" "http://127.0.0.1:${GATEWAY_SERVICE_PORT}/actuator/health"
      wait_eureka_app "${eureka_app}" "${EUREKA_APP_MAX_ATTEMPTS}" "${EUREKA_APP_SLEEP_SECONDS}"
      ;;
    *)
      [[ -n "${eureka_app}" ]] || return 0
      wait_eureka_app "${eureka_app}" "${EUREKA_APP_MAX_ATTEMPTS}" "${EUREKA_APP_SLEEP_SECONDS}"
      ;;
  esac
}

main() {
  local service_name="${1:-}"
  local requested_tag="${2:-}"
  local image_tag_var
  local effective_tag
  local required_profile
  local active_compose_profiles
  local eureka_app

  if [[ -z "${service_name}" || "${service_name}" == "-h" || "${service_name}" == "--help" ]]; then
    usage
    exit 0
  fi

  [[ -f "${ENV_FILE}" ]] || fail "${ENV_FILE} not found. Run scripts/gcp-load-secrets.sh first."
  gcp_service_exists "${service_name}" || fail "Unknown service in GCP registry: ${service_name}"

  require_command docker
  require_command curl
  require_command grep
  require_command awk

  CONFIG_SERVICE_PORT="$(read_env_value CONFIG_SERVICE_PORT)"
  EUREKA_SERVICE_PORT="$(read_env_value EUREKA_SERVICE_PORT)"
  GATEWAY_SERVICE_PORT="$(read_env_value GATEWAY_SERVICE_PORT)"
  active_compose_profiles="${COMPOSE_PROFILES:-$(read_optional_env_value COMPOSE_PROFILES)}"
  required_profile="$(gcp_service_required_profile "${service_name}")"

  if ! gcp_profile_enabled "${required_profile}" "${active_compose_profiles}"; then
    fail "${service_name} requires COMPOSE_PROFILES=${required_profile}"
  fi

  image_tag_var="$(gcp_service_image_tag_var "${service_name}")"

  if [[ -n "${requested_tag}" ]]; then
    validate_image_tag_value "${requested_tag}"
    update_env_value "${image_tag_var}" "${requested_tag}"
    effective_tag="${requested_tag}"
    log "Updated ${image_tag_var}=${effective_tag} in ${ENV_FILE}"
  else
    effective_tag="$(read_env_value "${image_tag_var}")"
    validate_image_tag_value "${effective_tag}"
  fi

  # Docker Compose gives the current shell environment precedence over --env-file.
  # Keep the process environment aligned with env/gcp.env so a stale exported
  # SERVICE_IMAGE_TAG cannot override the tag that this script just selected.
  export "${image_tag_var}=${effective_tag}"

  if [[ "${SKIP_GCLOUD_AUTH:-false}" != "true" ]]; then
    require_command gcloud
    log "Authenticating Docker with Artifact Registry..."
    gcloud auth configure-docker "$(read_env_value GCP_REGION)-docker.pkg.dev" --quiet
  fi

  SERVICE_NAME="${service_name}"
  eureka_app="$(gcp_service_eureka_app "${service_name}")"

  log "Pulling ${service_name}:${effective_tag}..."
  "${COMPOSE[@]}" pull "${service_name}"
  "${COMPOSE[@]}" images "${service_name}" || true

  log "Recreating ${service_name} without dependencies..."
  "${COMPOSE[@]}" up -d --no-deps --force-recreate "${service_name}"

  wait_deployed_service "${service_name}" "${eureka_app}"

  log "${service_name} deployed with ${image_tag_var}=${effective_tag}"
}

main "$@"
