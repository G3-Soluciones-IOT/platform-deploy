#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="env/gcp.env"
COMPOSE_FILE="docker/docker-compose.gcp.yml"

docker compose \
  --env-file "${ENV_FILE}" \
  -f "${COMPOSE_FILE}" \
  down