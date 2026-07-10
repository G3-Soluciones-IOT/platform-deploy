#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This file is a library and must be sourced." >&2
  exit 1
fi

GCP_SERVICES_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GCP_SERVICES_ROOT_DIR="$(cd -- "${GCP_SERVICES_LIB_DIR}/../.." && pwd)"
GCP_SERVICE_REGISTRY_FILE="${GCP_SERVICE_REGISTRY_FILE:-${GCP_SERVICES_ROOT_DIR}/config/gcp-services.env}"

gcp_services_registry_exists() {
  [[ -f "${GCP_SERVICE_REGISTRY_FILE}" ]]
}

gcp_services_rows() {
  local line

  gcp_services_registry_exists || {
    echo "[ERROR] Service registry not found: ${GCP_SERVICE_REGISTRY_FILE}" >&2
    return 1
  }

  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    printf '%s\n' "${line}"
  done < "${GCP_SERVICE_REGISTRY_FILE}"
}

gcp_profile_enabled() {
  local required_profile="$1"
  local active_profiles="${2:-}"

  [[ -z "${required_profile}" ]] && return 0
  [[ ",${active_profiles}," == *",${required_profile},"* ]]
}

gcp_service_exists() {
  local target_service="$1"
  local service_name
  local image_tag_var
  local eureka_app
  local openapi
  local datasource_prefix
  local group
  local required_profile

  while IFS='|' read -r service_name image_tag_var eureka_app openapi datasource_prefix group required_profile; do
    [[ "${service_name}" == "${target_service}" ]] && return 0
  done < <(gcp_services_rows)

  return 1
}

gcp_service_row() {
  local target_service="$1"
  local service_name
  local image_tag_var
  local eureka_app
  local openapi
  local datasource_prefix
  local group
  local required_profile

  while IFS='|' read -r service_name image_tag_var eureka_app openapi datasource_prefix group required_profile; do
    if [[ "${service_name}" == "${target_service}" ]]; then
      printf '%s|%s|%s|%s|%s|%s|%s\n' \
        "${service_name}" \
        "${image_tag_var}" \
        "${eureka_app}" \
        "${openapi}" \
        "${datasource_prefix}" \
        "${group}" \
        "${required_profile}"
      return 0
    fi
  done < <(gcp_services_rows)

  return 1
}

gcp_service_image_tag_var() {
  local service_name="$1"
  local row

  row="$(gcp_service_row "${service_name}")" || return 1
  IFS='|' read -r _service image_tag_var _eureka _openapi _prefix _group _profile <<< "${row}"
  printf '%s\n' "${image_tag_var}"
}

gcp_service_eureka_app() {
  local service_name="$1"
  local row

  row="$(gcp_service_row "${service_name}")" || return 1
  IFS='|' read -r _service _image_tag_var eureka_app _openapi _prefix _group _profile <<< "${row}"
  printf '%s\n' "${eureka_app}"
}

gcp_service_required_profile() {
  local service_name="$1"
  local row

  row="$(gcp_service_row "${service_name}")" || return 1
  IFS='|' read -r _service _image_tag_var _eureka _openapi _prefix _group required_profile <<< "${row}"
  printf '%s\n' "${required_profile}"
}

gcp_service_image_tag_vars() {
  local active_profiles="${1:-}"
  local service_name
  local image_tag_var
  local eureka_app
  local openapi
  local datasource_prefix
  local group
  local required_profile

  while IFS='|' read -r service_name image_tag_var eureka_app openapi datasource_prefix group required_profile; do
    gcp_profile_enabled "${required_profile}" "${active_profiles}" || continue
    printf '%s\n' "${image_tag_var}"
  done < <(gcp_services_rows)
}

gcp_service_names_by_group() {
  local target_group="$1"
  local active_profiles="${2:-}"
  local service_name
  local image_tag_var
  local eureka_app
  local openapi
  local datasource_prefix
  local group
  local required_profile

  while IFS='|' read -r service_name image_tag_var eureka_app openapi datasource_prefix group required_profile; do
    [[ "${group}" == "${target_group}" ]] || continue
    gcp_profile_enabled "${required_profile}" "${active_profiles}" || continue
    printf '%s\n' "${service_name}"
  done < <(gcp_services_rows)
}

gcp_service_names() {
  local active_profiles="${1:-}"
  local service_name
  local image_tag_var
  local eureka_app
  local openapi
  local datasource_prefix
  local group
  local required_profile

  while IFS='|' read -r service_name image_tag_var eureka_app openapi datasource_prefix group required_profile; do
    gcp_profile_enabled "${required_profile}" "${active_profiles}" || continue
    printf '%s\n' "${service_name}"
  done < <(gcp_services_rows)
}

gcp_service_eureka_apps_by_group() {
  local target_group="$1"
  local active_profiles="${2:-}"
  local service_name
  local image_tag_var
  local eureka_app
  local openapi
  local datasource_prefix
  local group
  local required_profile

  while IFS='|' read -r service_name image_tag_var eureka_app openapi datasource_prefix group required_profile; do
    [[ "${group}" == "${target_group}" ]] || continue
    [[ -n "${eureka_app}" ]] || continue
    gcp_profile_enabled "${required_profile}" "${active_profiles}" || continue
    printf '%s\n' "${eureka_app}"
  done < <(gcp_services_rows)
}

gcp_service_openapi_names() {
  local active_profiles="${1:-}"
  local service_name
  local image_tag_var
  local eureka_app
  local openapi
  local datasource_prefix
  local group
  local required_profile

  while IFS='|' read -r service_name image_tag_var eureka_app openapi datasource_prefix group required_profile; do
    [[ "${openapi}" == "true" ]] || continue
    gcp_profile_enabled "${required_profile}" "${active_profiles}" || continue
    printf '%s\n' "${service_name}"
  done < <(gcp_services_rows)
}

gcp_service_runtime_vars() {
  local active_profiles="${1:-}"
  local service_name
  local image_tag_var
  local eureka_app
  local openapi
  local datasource_prefix
  local group
  local required_profile

  while IFS='|' read -r service_name image_tag_var eureka_app openapi datasource_prefix group required_profile; do
    [[ -n "${datasource_prefix}" ]] || continue
    gcp_profile_enabled "${required_profile}" "${active_profiles}" || continue
    printf '%s_SPRING_DATASOURCE_URL\n' "${datasource_prefix}"
    printf '%s_SPRING_DATASOURCE_USERNAME\n' "${datasource_prefix}"
    printf '%s_SPRING_DATASOURCE_PASSWORD\n' "${datasource_prefix}"
  done < <(gcp_services_rows)
}

gcp_all_eureka_apps() {
  local active_profiles="${1:-}"
  local service_name
  local image_tag_var
  local eureka_app
  local openapi
  local datasource_prefix
  local group
  local required_profile

  while IFS='|' read -r service_name image_tag_var eureka_app openapi datasource_prefix group required_profile; do
    [[ -n "${eureka_app}" ]] || continue
    gcp_profile_enabled "${required_profile}" "${active_profiles}" || continue
    printf '%s\n' "${eureka_app}"
  done < <(gcp_services_rows)
}
