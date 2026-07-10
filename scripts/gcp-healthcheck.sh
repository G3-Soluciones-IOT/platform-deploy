#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/env/gcp.env"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/gcp-services.sh"

if [ ! -f "${ENV_FILE}" ]; then
  echo "[ERROR] ${ENV_FILE} not found."
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

CONFIG_SERVICE_PORT="${CONFIG_SERVICE_PORT:-8888}"
EUREKA_SERVICE_PORT="${EUREKA_SERVICE_PORT:-8761}"
GATEWAY_SERVICE_PORT="${GATEWAY_SERVICE_PORT:-8080}"

mapfile -t EUREKA_APPS < <(gcp_all_eureka_apps "${COMPOSE_PROFILES:-}")

check_http() {
  local name="$1"
  local url="$2"

  echo "Checking ${name}..."
  curl -fsS "${url}"
  echo
}

check_eureka_app() {
  local app_name="$1"
  local url="http://localhost:${EUREKA_SERVICE_PORT}/eureka/apps/${app_name}"

  echo "Checking Eureka registration: ${app_name}..."
  if ! curl -fsS "${url}" | grep -q "<status>UP</status>"; then
    echo "[ERROR] ${app_name} is not registered as UP in Eureka."
    exit 1
  fi
  echo "${app_name} is UP"
}

echo "Waiting for services to start..."
sleep 20

check_http "config-service" "http://localhost:${CONFIG_SERVICE_PORT}/actuator/health"
check_http "eureka-service" "http://localhost:${EUREKA_SERVICE_PORT}/actuator/health"
check_http "gateway-service" "http://localhost:${GATEWAY_SERVICE_PORT}/actuator/health"

echo "Checking IAM JWKS through gateway..."
curl -fsS "http://localhost:${GATEWAY_SERVICE_PORT}/api/v1/jwks/.well-known/jwks.json"
echo

for app_name in "${EUREKA_APPS[@]}"; do
  check_eureka_app "${app_name}"
done

echo "GCP platform and Eureka registrations are healthy."
