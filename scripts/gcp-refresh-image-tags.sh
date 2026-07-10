#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/env/gcp.env"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/gcp-services.sh"

usage() {
  cat <<'USAGE'
Usage:
  scripts/gcp-refresh-image-tags.sh [service-name ...]

Examples:
  scripts/gcp-refresh-image-tags.sh payments-service
  scripts/gcp-refresh-image-tags.sh payments-service meal-plans-service
  scripts/gcp-refresh-image-tags.sh

Without service names, the script refreshes every active service from the GCP
service registry. It chooses the latest Artifact Registry tag matching
sha-<7-hex-character> and updates env/gcp.env.
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

latest_sha_tag() {
  local service_name="$1"
  local image_path="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${GAR_REPOSITORY}/${service_name}"
  local raw_tag
  local tag

  raw_tag="$({
    gcloud artifacts docker tags list "${image_path}" \
      --project="${GCP_PROJECT_ID}" \
      --sort-by='~UPDATE_TIME' \
      --limit=20 \
      --format='value(TAG)' \
      2>/dev/null \
      | grep -E '(^|:)sha-[0-9a-f]{7}$' \
      | head -n 1
  } || true)"

  [[ -n "${raw_tag}" ]] || return 1

  tag="${raw_tag##*:}"
  [[ "${tag}" =~ ^sha-[0-9a-f]{7}$ ]] || return 1
  printf '%s\n' "${tag}"
}

refresh_service() {
  local service_name="$1"
  local image_tag_var
  local tag
  local required_profile

  gcp_service_exists "${service_name}" || fail "Unknown service in GCP registry: ${service_name}"

  required_profile="$(gcp_service_required_profile "${service_name}")"
  if ! gcp_profile_enabled "${required_profile}" "${ACTIVE_COMPOSE_PROFILES}"; then
    fail "${service_name} requires COMPOSE_PROFILES=${required_profile}"
  fi

  image_tag_var="$(gcp_service_image_tag_var "${service_name}")"
  log "Looking up latest immutable tag for ${service_name}..."
  tag="$(latest_sha_tag "${service_name}")" || fail "No sha-<7-hex-character> tag found for ${service_name}"

  update_env_value "${image_tag_var}" "${tag}"
  log "Updated ${image_tag_var}=${tag}"
}

main() {
  local services=("$@")

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  [[ -f "${ENV_FILE}" ]] || fail "${ENV_FILE} not found. Run scripts/gcp-load-secrets.sh first."

  require_command gcloud
  require_command grep
  require_command awk
  require_command head

  GCP_PROJECT_ID="$(read_env_value GCP_PROJECT_ID)"
  GCP_REGION="$(read_env_value GCP_REGION)"
  GAR_REPOSITORY="$(read_env_value GAR_REPOSITORY)"
  ACTIVE_COMPOSE_PROFILES="${COMPOSE_PROFILES:-$(read_optional_env_value COMPOSE_PROFILES)}"

  if [[ "${#services[@]}" -eq 0 ]]; then
    mapfile -t services < <(gcp_service_names "${ACTIVE_COMPOSE_PROFILES}")
  fi

  for service_name in "${services[@]}"; do
    refresh_service "${service_name}"
  done

  log "Image tags refreshed in ${ENV_FILE}"
}

main "$@"
