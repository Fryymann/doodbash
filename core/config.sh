#!/usr/bin/env bash
# shellcheck shell=bash
# Literal DoodBash configuration storage and file loading.

if [[ -n "${_DOOD_CONFIG_SH_LOADED:-}" ]]; then
  return 0
fi
_DOOD_CONFIG_SH_LOADED=1

declare -gA DOOD_CFG=()
declare -gA DOOD_CFG_SOURCE=()

dood_config_key_valid() {
  local key="${1:-}"
  [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]]
}

dood_config_require_key() {
  local key="${1:-}"
  if dood_config_key_valid "$key"; then
    return 0
  fi
  printf 'doodbash: invalid configuration key: %s\n' "$key" >&2
  return 2
}

dood_config_reset() {
  DOOD_CFG=()
  DOOD_CFG_SOURCE=()
}

dood_config_set() {
  local key="$1" value="$2" source="$3"
  dood_config_require_key "$key" || return
  DOOD_CFG["$key"]="$value"
  DOOD_CFG_SOURCE["$key"]="$source"
}

dood_config_load_file() {
  local path="$1" requirement="${2:-required}"
  local line key value line_number=0 read_status
  local -A pending_values=()
  local -A pending_sources=()

  case "$requirement" in
    required | optional) ;;
    *)
      printf 'doodbash: invalid configuration requirement: %s\n' "$requirement" >&2
      return 2
      ;;
  esac

  if [[ ! -f "$path" ]]; then
    [[ "$requirement" == optional ]] && return 0
    printf 'doodbash: required configuration file not found: %s\n' "$path" >&2
    return 2
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    line="${line%$'\r'}"
    [[ -z "$line" || "${line:0:1}" == '#' ]] && continue

    if [[ "$line" != *=* ]]; then
      printf 'doodbash: invalid configuration record at %s:%d: missing =\n' \
        "$path" "$line_number" >&2
      return 2
    fi

    key="${line%%=*}"
    if ! dood_config_key_valid "$key"; then
      printf 'doodbash: invalid configuration key at %s:%d: %s\n' \
        "$path" "$line_number" "$key" >&2
      return 2
    fi

    value="${line#*=}"
    pending_values["$key"]="$value"
    pending_sources["$key"]="$path:$line_number"
  done <"$path"
  read_status=$?

  if (( read_status != 0 )); then
    printf 'doodbash: unable to read configuration file: %s\n' "$path" >&2
    return 2
  fi

  for key in "${!pending_values[@]}"; do
    dood_config_set "$key" "${pending_values[$key]}" "${pending_sources[$key]}" || return
  done
}

dood_config_get() {
  local key="$1" default_value="${2:-}"
  dood_config_require_key "$key" || return
  if [[ -v "DOOD_CFG[$key]" ]]; then
    printf '%s\n' "${DOOD_CFG[$key]}"
  else
    printf '%s\n' "$default_value"
  fi
}

dood_config_has() {
  local key="$1"
  dood_config_require_key "$key" || return
  [[ -v "DOOD_CFG[$key]" ]]
}

dood_config_source() {
  local key="$1"
  dood_config_require_key "$key" || return
  [[ -v "DOOD_CFG_SOURCE[$key]" ]] || return 1
  printf '%s\n' "${DOOD_CFG_SOURCE[$key]}"
}
