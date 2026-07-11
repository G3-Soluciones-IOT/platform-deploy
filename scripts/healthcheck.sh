#!/usr/bin/env bash
set -euo pipefail

check_http() {
  local name="$1"
  local url="$2"

  printf "Checking %-28s %s ... " "${name}" "${url}"

  if curl -fsS "${url}" >/dev/null 2>&1; then
    echo "OK"
  else
    echo "FAIL"
    return 1
  fi
}

check_eureka_app() {
  local app_name="$1"
  local url="http://localhost:8761/eureka/apps/${app_name}"

  printf "Checking Eureka app %-18s ... " "${app_name}"

  if curl -fsS "${url}" | grep -q "<status>UP</status>"; then
    echo "OK"
  else
    echo "FAIL"
    return 1
  fi
}

echo "Checking JameoFit local platform..."
echo

check_http "config-service" "http://localhost:8888/actuator/health"
check_http "eureka-service" "http://localhost:8761/actuator/health"
check_http "iam-service" "http://localhost:8081/actuator/health"
check_http "goals-service" "http://localhost:8083/actuator/health"
check_http "meal-plans-service" "http://localhost:8084/actuator/health"
check_http "payments-service" "http://localhost:8092/actuator/health"
check_http "nutritionist-service" "http://localhost:8085/actuator/health"
check_http "profiles-service" "http://localhost:8086/actuator/health"
check_http "recipes-service" "http://localhost:8087/actuator/health"
check_http "tracking-service" "http://localhost:8089/actuator/health"
check_http "iot-service" "http://localhost:8093/actuator/health"
check_http "nutrition-ai-service" "http://localhost:8091/actuator/health"
check_http "gateway-service" "http://localhost:8080/actuator/health"

echo
echo "Checking Eureka registrations..."
echo

check_eureka_app "IAM-SERVICE"
check_eureka_app "GOALS-SERVICE"
check_eureka_app "MEAL-PLANS-SERVICE"
check_eureka_app "PAYMENTS-SERVICE"
check_eureka_app "NUTRITIONIST-SERVICE"
check_eureka_app "PROFILES-SERVICE"
check_eureka_app "RECIPES-SERVICE"
check_eureka_app "TRACKING-SERVICE"
check_eureka_app "IOT-SERVICE"
check_eureka_app "NUTRITION-AI-SERVICE"
check_eureka_app "GATEWAY-SERVICE"

echo
echo "All local healthchecks passed."
