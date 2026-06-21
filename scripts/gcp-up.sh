#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/env/gcp.env"
COMPOSE_FILE="${ROOT_DIR}/docker/docker-compose.gcp.yml"
REQUIRED_IMAGE_TAGS=(
  CONFIG_SERVICE_IMAGE_TAG
  EUREKA_SERVICE_IMAGE_TAG
  IAM_SERVICE_IMAGE_TAG
  GATEWAY_SERVICE_IMAGE_TAG
  GOALS_SERVICE_IMAGE_TAG
  MEAL_PLANS_SERVICE_IMAGE_TAG
  PROFILES_SERVICE_IMAGE_TAG
  RECIPES_SERVICE_IMAGE_TAG
  TRACKING_SERVICE_IMAGE_TAG
)

if [ ! -f "${ENV_FILE}" ]; then
  echo "[ERROR] ${ENV_FILE} not found."
  echo "Run scripts/gcp-load-secrets.sh first."
  exit 1
fi

validate_image_tag() {
  local variable_name="$1"
  local value

  value="$(grep -m 1 "^${variable_name}=" "${ENV_FILE}" | cut -d '=' -f 2- || true)"
  if [[ ! "${value}" =~ ^sha-[0-9a-f]{7}$ ]]; then
    echo "[ERROR] ${variable_name} in ${ENV_FILE} must use the immutable sha-<7-hex-character> format."
    exit 1
  fi
}

for variable_name in "${REQUIRED_IMAGE_TAGS[@]}"; do
  validate_image_tag "${variable_name}"
done

if [[ ",${COMPOSE_PROFILES:-}," == *,communication,* ]]; then
  validate_image_tag COMMUNICATION_SERVICE_IMAGE_TAG
  if ! grep -q '^COMMUNICATION_MONGODB_URI=' "${ENV_FILE}"; then
    echo "[ERROR] communication profile requires COMMUNICATION_MONGODB_SECRET_ID when running gcp-load-secrets.sh."
    exit 1
  fi
fi

echo "Authenticating Docker with Artifact Registry..."
gcloud auth configure-docker southamerica-west1-docker.pkg.dev --quiet

echo "Pulling images..."
docker compose \
  --env-file "${ENV_FILE}" \
  -f "${COMPOSE_FILE}" \
  pull

echo "Starting JameoFit GCP platform..."
docker compose \
  --env-file "${ENV_FILE}" \
  -f "${COMPOSE_FILE}" \
  up -d

echo "Containers:"
docker compose \
  --env-file "${ENV_FILE}" \
  -f "${COMPOSE_FILE}" \
  ps
