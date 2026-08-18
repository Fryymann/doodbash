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
comments_and_blank_lines_are_ignored() {
  # shellcheck source=/dev/null
  source "$ROOT/core/config.sh"
  new_test_tmpdir || return 1
  local tmp="$REPLY" config="$REPLY/comments.conf"
  {
    printf '# leading comment\n'
    printf '\n'
    printf 'DOOD_COLOR=auto\n'
    printf '#DOOD_EDITOR=nvim\n'
    printf '\n'
    printf 'DOOD_PROFILE=personal\n'
  } >"$config"

  dood_config_reset
  dood_config_load_file "$config" required || return 1

  assert_eq auto "$(dood_config_get DOOD_COLOR)" 'record after ignored lines is loaded' || return 1
  assert_eq "$config:3" "$(dood_config_source DOOD_COLOR)" 'ignored lines still advance the line counter' || return 1
  if dood_config_has DOOD_EDITOR; then
    fail 'commented record was loaded'
    return 1
  fi
  assert_eq "$config:6" "$(dood_config_source DOOD_PROFILE)" 'provenance stays accurate after ignored lines'
}

run_test 'comment and blank lines are ignored' comments_and_blank_lines_are_ignored

values_keep_everything_after_the_first_equals() {
  # shellcheck source=/dev/null
  source "$ROOT/core/config.sh"
  new_test_tmpdir || return 1
  local tmp="$REPLY" config="$REPLY/values.conf"
  {
    printf 'DOOD_QUERY=a=b=c\n'
    printf 'DOOD_EMPTY=\n'
    printf 'DOOD_SPACED=two words\n'
  } >"$config"

  dood_config_reset
  dood_config_load_file "$config" required || return 1

  assert_eq 'a=b=c' "$(dood_config_get DOOD_QUERY)" 'additional equals characters stay in the value' || return 1
  assert_eq '' "$(dood_config_get DOOD_EMPTY MISSING)" 'an empty value is a set value, not a default' || return 1
  assert_eq 'two words' "$(dood_config_get DOOD_SPACED)" 'unquoted spaces stay in the value'
}

run_test 'values keep everything after the first equals' values_keep_everything_after_the_first_equals

crlf_line_endings_are_tolerated() {
  # shellcheck source=/dev/null
  source "$ROOT/core/config.sh"
  new_test_tmpdir || return 1
  local tmp="$REPLY" config="$REPLY/crlf.conf"
  printf 'DOOD_COLOR=auto\r\nDOOD_PROFILE=personal\r\n' >"$config"

  dood_config_reset
  dood_config_load_file "$config" required || return 1

  assert_eq auto "$(dood_config_get DOOD_COLOR)" 'trailing carriage return is removed from the value' || return 1
  assert_eq personal "$(dood_config_get DOOD_PROFILE)" 'every CRLF record is tolerated'
}

run_test 'CRLF line endings are tolerated' crlf_line_endings_are_tolerated

a_missing_file_obeys_its_requirement_mode() {
  # shellcheck source=/dev/null
  source "$ROOT/core/config.sh"
  new_test_tmpdir || return 1
  local tmp="$REPLY" config="$REPLY/absent.conf" output

  dood_config_reset
  if ! dood_config_load_file "$config" optional; then
    fail 'a missing optional file was not accepted'
    return 1
  fi

  if output="$(dood_config_load_file "$config" required 2>&1)"; then
    fail 'a missing required file was accepted'
    return 1
  fi
  assert_contains "$output" "$config" 'a missing required file names the path' || return 1

  if dood_config_load_file "$config" >/dev/null 2>&1; then
    fail 'the default requirement mode accepted a missing file'
    return 1
  fi
}

run_test 'a missing file obeys its requirement mode' a_missing_file_obeys_its_requirement_mode

a_later_file_overrides_an_earlier_value() {
  # shellcheck source=/dev/null
  source "$ROOT/core/config.sh"
  new_test_tmpdir || return 1
  local tmp="$REPLY" base="$REPLY/base.conf" over="$REPLY/over.conf"
  {
    printf 'DOOD_COLOR=auto\n'
    printf 'DOOD_EDITOR=nvim\n'
  } >"$base"
  printf 'DOOD_COLOR=never\n' >"$over"

  dood_config_reset
  dood_config_load_file "$base" required || return 1
  dood_config_load_file "$over" required || return 1

  assert_eq never "$(dood_config_get DOOD_COLOR)" 'the later file wins the value' || return 1
  assert_eq "$over:1" "$(dood_config_source DOOD_COLOR)" 'the later file wins the provenance' || return 1
  assert_eq nvim "$(dood_config_get DOOD_EDITOR)" 'a key the later file omits keeps its value' || return 1
  assert_eq "$base:2" "$(dood_config_source DOOD_EDITOR)" 'a key the later file omits keeps its provenance'
}

run_test 'a later file overrides an earlier value' a_later_file_overrides_an_earlier_value

the_shipped_defaults_file_loads_as_a_required_layer() {
  # shellcheck source=/dev/null
  source "$ROOT/core/config.sh"
  local defaults="$ROOT/config/defaults.conf"

  if [[ ! -f "$defaults" ]]; then
    fail 'config/defaults.conf is shipped'
    return 1
  fi

  dood_config_reset
  dood_config_load_file "$defaults" required || return 1

  assert_eq auto "$(dood_config_get DOOD_COLOR)" 'defaults supply the color policy' || return 1
  assert_contains "$(dood_config_source DOOD_COLOR)" "$defaults:" 'defaults provenance names the shipped file' || return 1

  local selector
  for selector in DOOD_PROFILE DOOD_HOST_OVERRIDE; do
    if dood_config_has "$selector"; then
      fail "defaults must not set the selection input $selector"
      return 1
    fi
  done
}

run_test 'the shipped defaults file loads as a required layer' the_shipped_defaults_file_loads_as_a_required_layer

finish_tests
