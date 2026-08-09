#!/usr/bin/env bash
# Dependency-free test helpers for DoodBash.

set -u

DOOD_TEST_COUNT=0
DOOD_TEST_FAILURES=0
DOOD_TEST_TMPDIRS=()

fail() {
  printf 'not ok - %s\n' "$1" >&2
  DOOD_TEST_FAILURES=$((DOOD_TEST_FAILURES + 1))
}

pass() {
  printf 'ok - %s\n' "$1"
}

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  if [[ "$actual" == "$expected" ]]; then
    return 0
  fi
  printf '  expected: %q\n  actual:   %q\n' "$expected" "$actual" >&2
  fail "$message"
  return 1
}

assert_contains() {
  local haystack="$1" needle="$2" message="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    return 0
  fi
  printf '  missing: %q\n  output:  %q\n' "$needle" "$haystack" >&2
  fail "$message"
  return 1
}

assert_file_absent() {
  local path="$1" message="$2"
  if [[ ! -e "$path" ]]; then
    return 0
  fi
  printf '  unexpected path: %s\n' "$path" >&2
  fail "$message"
  return 1
}

new_test_tmpdir() {
  REPLY="$(mktemp -d "${TMPDIR:-/tmp}/doodbash-test-XXXXXX")" || return 1
  DOOD_TEST_TMPDIRS+=("$REPLY")
}

cleanup_test_tmpdirs() {
  local dir
  for dir in "${DOOD_TEST_TMPDIRS[@]}"; do
    [[ -n "$dir" && -d "$dir" ]] && rm -rf -- "$dir"
  done
  DOOD_TEST_TMPDIRS=()
}

trap cleanup_test_tmpdirs EXIT

run_test() {
  local name="$1" function_name="$2"
  local failures_before="$DOOD_TEST_FAILURES"
  DOOD_TEST_COUNT=$((DOOD_TEST_COUNT + 1))
  if "$function_name"; then
    pass "$name"
  elif (( DOOD_TEST_FAILURES == failures_before )); then
    fail "$name"
  fi
}

finish_tests() {
  cleanup_test_tmpdirs
  trap - EXIT

  printf '1..%d\n' "$DOOD_TEST_COUNT"
  if (( DOOD_TEST_FAILURES > 0 )); then
    printf '# %d failure(s)\n' "$DOOD_TEST_FAILURES" >&2
    return 1
  fi
}
