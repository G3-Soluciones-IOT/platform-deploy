#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker/docker-compose.local.yml"
ENV_FILE="${ROOT_DIR}/env/local.env"

COMPOSE=(docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")

REMOVE_VOLUMES="${REMOVE_VOLUMES:-false}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "WARN: ${ENV_FILE} not found. Using compose without env file may fail."
fi

echo "Stopping JameoFit local platform..."

if [[ "${REMOVE_VOLUMES}" == "true" ]]; then
  echo "Stopping containers and removing volumes..."
  "${COMPOSE[@]}" down -v --remove-orphans
else
  echo "Stopping containers without removing volumes..."
  "${COMPOSE[@]}" down --remove-orphans
fi

echo "Done."