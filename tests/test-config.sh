#!/usr/bin/env bash
set -u

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=tests/testlib.sh
source "$ROOT/tests/testlib.sh"

literal_config_is_data() {
  if [[ ! -r "$ROOT/core/config.sh" ]]; then
    fail 'configuration library exists'
    return 1
  fi

  # shellcheck source=/dev/null
  source "$ROOT/core/config.sh"
  new_test_tmpdir || return 1
  local tmp="$REPLY"
  local config="$tmp/literal.conf" marker="$tmp/executed"
  {
    printf 'DOOD_COLOR=auto\n'
    printf 'DANGER=$(touch %s)\n' "$marker"
  } >"$config"

  dood_config_reset
  dood_config_load_file "$config" required || return 1

  assert_eq 'auto' "$(dood_config_get DOOD_COLOR)" 'literal value is loaded' || return 1
  assert_eq "\$(touch $marker)" "$(dood_config_get DANGER)" 'command substitution remains literal' || return 1
  assert_file_absent "$marker" 'configuration value is never executed' || return 1
  assert_eq "$config:2" "$(dood_config_source DANGER)" 'source provenance includes file and line'
}

run_test 'literal configuration is parsed as data' literal_config_is_data

invalid_config_records_are_rejected() {
  # shellcheck source=/dev/null
  source "$ROOT/core/config.sh"
  new_test_tmpdir || return 1
  local tmp="$REPLY" record config output

  for record in 'MISSING_EQUALS' ' LEADING_SPACE=value' 'BAD-KEY=value'; do
    config="$tmp/invalid.conf"
    printf '%s\n' "$record" >"$config"
    dood_config_reset
    if output="$(dood_config_load_file "$config" required 2>&1)"; then
      fail "invalid record was accepted: $record"
      return 1
    fi
    assert_contains "$output" "$config:1" "invalid record reports source: $record" || return 1
  done
}

run_test 'invalid configuration records are rejected' invalid_config_records_are_rejected

hostile_api_keys_are_rejected() {
  # shellcheck source=/dev/null
  source "$ROOT/core/config.sh"
  new_test_tmpdir || return 1
  local tmp="$REPLY" marker="$REPLY/executed"
  local hostile="\$(touch $marker)" function_name failed=0

  dood_config_reset
  for function_name in dood_config_get dood_config_has dood_config_source; do
    if "$function_name" "$hostile" >/dev/null 2>&1; then
      fail "$function_name accepted a hostile key"
      failed=1
    fi
  done
  if dood_config_set "$hostile" value test:1 >/dev/null 2>&1; then
    fail 'dood_config_set accepted a hostile key'
    failed=1
  fi
  assert_file_absent "$marker" 'hostile API key is never evaluated' || failed=1
  (( failed == 0 ))
}

run_test 'hostile API keys are rejected before array access' hostile_api_keys_are_rejected

failed_file_load_is_atomic() {
  # shellcheck source=/dev/null
  source "$ROOT/core/config.sh"
  new_test_tmpdir || return 1
  local tmp="$REPLY" config="$REPLY/partial.conf"
  {
    printf 'KEEP=changed\n'
    printf 'NEW=value\n'
    printf 'BAD-KEY=invalid\n'
  } >"$config"

  dood_config_reset
  dood_config_set KEEP original baseline:1
  if dood_config_load_file "$config" required >/dev/null 2>&1; then
    fail 'partially invalid file was accepted'
    return 1
  fi

  assert_eq original "$(dood_config_get KEEP)" 'failed file preserves prior value' || return 1
  assert_eq baseline:1 "$(dood_config_source KEEP)" 'failed file preserves prior provenance' || return 1
  if dood_config_has NEW; then
    fail 'failed file leaked a new value'
    return 1
  fi
}

run_test 'failed configuration file load is atomic' failed_file_load_is_atomic

invalid_requirement_is_rejected() {
  # shellcheck source=/dev/null
  source "$ROOT/core/config.sh"
  new_test_tmpdir || return 1
  local tmp="$REPLY" config="$REPLY/config.conf" output
  printf 'KEY=value\n' >"$config"

  dood_config_reset
  if output="$(dood_config_load_file "$config" sometimes 2>&1)"; then
    fail 'invalid requirement mode was accepted'
    return 1
  fi
  assert_contains "$output" 'invalid configuration requirement' 'invalid requirement reports a usage error'
}

run_test 'configuration requirement mode is explicit' invalid_requirement_is_rejected

unreadable_file_load_fails_atomically() {
  # shellcheck source=/dev/null
  source "$ROOT/core/config.sh"
  new_test_tmpdir || return 1
  local tmp="$REPLY" config="$REPLY/unreadable.conf" output
  printf 'KEEP=changed\n' >"$config"
  chmod 000 "$config"

  dood_config_reset
  dood_config_set KEEP original baseline:1
  if output="$(dood_config_load_file "$config" required 2>&1)"; then
    chmod 600 "$config"
    fail 'unreadable required file was accepted'
    return 1
  fi
  chmod 600 "$config"

  assert_eq original "$(dood_config_get KEEP)" 'unreadable file preserves prior value' || return 1
  assert_eq baseline:1 "$(dood_config_source KEEP)" 'unreadable file preserves prior provenance' || return 1
  assert_contains "$output" "$config" 'unreadable file error identifies its path'
}

run_test 'unreadable configuration file fails atomically' unreadable_file_load_fails_atomically
finish_tests
