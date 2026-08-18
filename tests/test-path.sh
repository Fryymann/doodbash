#!/usr/bin/env bash
set -u

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=tests/testlib.sh
source "$ROOT/tests/testlib.sh"

PATH_FIXTURE_DIR="$ROOT/tests/fixtures/path"

# Read one PATH entry per line into PATH_FIXTURE. Never sources the fixture.
path_fixture_load() {
  local fixture="$1" line
  PATH_FIXTURE=()
  if [[ ! -f "$fixture" ]]; then
    printf '  missing fixture: %s\n' "$fixture" >&2
    return 1
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    PATH_FIXTURE+=("$line")
  done <"$fixture"
}

a_linux_fixture_loads_one_entry_per_line() {
  if ! path_fixture_load "$PATH_FIXTURE_DIR/linux.path"; then
    fail 'the linux PATH fixture is readable'
    return 1
  fi

  assert_eq 4 "${#PATH_FIXTURE[@]}" 'the linux fixture has one element per line' || return 1
  assert_eq '/home/ideans/.local/bin' "${PATH_FIXTURE[0]}" 'the first linux entry is preserved' || return 1
  assert_eq '/bin' "${PATH_FIXTURE[3]}" 'the last linux entry is preserved'
}

run_test 'a linux fixture loads one entry per line' a_linux_fixture_loads_one_entry_per_line

a_windows_entry_containing_spaces_stays_one_element() {
  if ! path_fixture_load "$PATH_FIXTURE_DIR/mixed-wsl.path"; then
    fail 'the mixed WSL PATH fixture is readable'
    return 1
  fi

  assert_eq 4 "${#PATH_FIXTURE[@]}" 'the mixed fixture has one element per line' || return 1
  assert_eq '/mnt/c/Program Files/WezTerm' "${PATH_FIXTURE[2]}" 'a Windows entry with spaces is one element' || return 1
  assert_eq '/mnt/c/Windows/System32' "${PATH_FIXTURE[3]}" 'the entry after a spaced entry is intact'
}

run_test 'a windows entry containing spaces stays one element' a_windows_entry_containing_spaces_stays_one_element

duplicate_entries_are_preserved_as_input_data() {
  if ! path_fixture_load "$PATH_FIXTURE_DIR/duplicates.path"; then
    fail 'the duplicate PATH fixture is readable'
    return 1
  fi

  assert_eq 5 "${#PATH_FIXTURE[@]}" 'the loader does not collapse duplicates' || return 1
  assert_eq '/usr/bin' "${PATH_FIXTURE[0]}" 'the first duplicate occurrence is kept' || return 1
  assert_eq '/usr/bin' "${PATH_FIXTURE[2]}" 'the later duplicate occurrence is kept'
}

run_test 'duplicate entries are preserved as input data' duplicate_entries_are_preserved_as_input_data

hostile_entries_stay_literal_and_execute_nothing() {
  new_test_tmpdir || return 1
  local tmp="$REPLY" saved_pwd="$PWD" status=0

  cd "$tmp" || return 1
  path_fixture_load "$PATH_FIXTURE_DIR/hostile.path" || status=1
  cd "$saved_pwd" || return 1

  if (( status != 0 )); then
    fail 'the hostile PATH fixture is readable'
    return 1
  fi

  assert_eq 4 "${#PATH_FIXTURE[@]}" 'the hostile fixture has one element per line' || return 1
  assert_eq '/tmp/$(touch SHOULD_NOT_EXIST)' "${PATH_FIXTURE[0]}" 'command substitution stays literal' || return 1
  assert_eq '/tmp/`touch SHOULD_NOT_EXIST_BACKTICK`' "${PATH_FIXTURE[1]}" 'backticks stay literal' || return 1
  assert_eq '/tmp/one; touch SHOULD_NOT_EXIST_SEMI' "${PATH_FIXTURE[2]}" 'a semicolon stays literal' || return 1
  assert_eq '/tmp/a b c' "${PATH_FIXTURE[3]}" 'internal spaces stay literal' || return 1

  local marker
  for marker in SHOULD_NOT_EXIST SHOULD_NOT_EXIST_BACKTICK SHOULD_NOT_EXIST_SEMI; do
    assert_file_absent "$tmp/$marker" "loading the fixture never created $marker" || return 1
    assert_file_absent "$ROOT/$marker" "loading the fixture never created $marker in the repository" || return 1
  done
}

run_test 'hostile entries stay literal and execute nothing' hostile_entries_stay_literal_and_execute_nothing
finish_tests
