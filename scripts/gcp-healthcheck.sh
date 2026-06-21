#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/env/gcp.env"

if [ ! -f "${ENV_FILE}" ]; then
  echo "[ERROR] ${ENV_FILE} not found."
  exit 1
fi

echo "Waiting for services to start..."
sleep 20

echo "Checking config-service..."
curl -fsS http://localhost:8888/actuator/health
echo

echo "Checking eureka-service..."
curl -fsS http://localhost:8761/actuator/health
echo

echo "Checking gateway-service..."
curl -fsS http://localhost:8080/actuator/health
echo

echo "Checking IAM JWKS through gateway..."
curl -fsS http://localhost:8080/api/v1/jwks/.well-known/jwks.json
echo

# TODO: add domain-service checks only after their gateway health routes are confirmed.
# communication-service is intentionally not checked; it is an optional profile.

echo "GCP platform base is healthy."
