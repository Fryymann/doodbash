#!/usr/bin/env bash
set -u

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=tests/testlib.sh
source "$ROOT/tests/testlib.sh"

silent_failure_after_prior_failure_is_counted() {
  local output
  output="$(bash -c '
    source "$1"
    DOOD_TEST_FAILURES=1
    silent_failure() { return 1; }
    run_test second silent_failure
    printf "failures=%s\n" "$DOOD_TEST_FAILURES"
  ' _ "$ROOT/tests/testlib.sh" 2>&1)"

  assert_contains "$output" 'failures=2' 'later silent failure increments the failure count'
}

run_test 'silent failures are counted after prior failures' silent_failure_after_prior_failure_is_counted
finish_tests
