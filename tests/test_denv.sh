#!/usr/bin/env bash
#
# tests/test_denv.sh - Automated Integration Test Suite for denv
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly SCRIPT_DIR
readonly DENV_BIN="${SCRIPT_DIR}/bin/denv"

tests_run=0
tests_passed=0
tests_failed=0

# Terminal colors
c_green=""
c_red=""
c_bold=""
c_reset=""
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  c_green=$'\033[32m'
  c_red=$'\033[31m'
  c_bold=$'\033[1m'
  c_reset=$'\033[0m'
fi

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-Assertion failed}"
  if [[ "$expected" != "$actual" ]]; then
    printf '%s[FAIL]%s %s (Expected: "%s", got: "%s")\n' "$c_red" "$c_reset" "$msg" "$expected" "$actual" >&2
    return 1
  fi
  return 0
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-Substring not found}"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf '%s[FAIL]%s %s (Looking for: "%s")\n' "$c_red" "$c_reset" "$msg" "$needle" >&2
    return 1
  fi
  return 0
}

run_test() {
  local test_name="$1"
  tests_run=$((tests_run + 1))
  printf '  Running %-50s ' "${test_name}..."

  local tmp_dir
  tmp_dir="$(mktemp -d "/tmp/denv-test.XXXXXXXXXX")"
  local failed=0

  (
    cd "$tmp_dir"
    "$test_name" "$tmp_dir"
  ) || failed=1

  rm -rf -- "$tmp_dir"

  if [[ "$failed" -eq 0 ]]; then
    tests_passed=$((tests_passed + 1))
    printf '%sPASS%s\n' "$c_green" "$c_reset"
  else
    tests_failed=$((tests_failed + 1))
    printf '%sFAIL%s\n' "$c_red" "$c_reset"
  fi
}

# --- Test Cases ---

test_help_and_version() {
  local tmp="$1"
  local out

  out="$("$DENV_BIN" --version)"
  assert_contains "$out" "denv version 1." "Version string check"

  out="$("$DENV_BIN" --help)"
  assert_contains "$out" "Universal direnv bootstrapper" "Help banner check"
  assert_contains "$out" "OPTIONS:" "Help options check"
}

test_invalid_flag() {
  local tmp="$1"
  local exit_code=0
  "$DENV_BIN" --unrecognized-option >/dev/null 2>&1 || exit_code=$?
  assert_eq "2" "$exit_code" "Invalid option should exit with EX_USAGE (2)"
}

test_fresh_envrc_creation() {
  local tmp="$1"
  "$DENV_BIN" -n "$tmp" >/dev/null 2>&1

  local envrc="${tmp}/.envrc"
  [[ -f "$envrc" ]] || { echo ".envrc was not created"; return 1; }

  local content
  content="$(cat "$envrc")"
  assert_contains "$content" "# >>> denv initialize >>>" "Start sentinel marker"
  assert_contains "$content" "# <<< denv initialize <<<" "End sentinel marker"
  assert_contains "$content" "dotenv_if_exists .env" "dotenv loading directive"
}

test_idempotency_without_force() {
  local tmp="$1"
  "$DENV_BIN" -n "$tmp" >/dev/null 2>&1
  local first_run
  first_run="$(cat "${tmp}/.envrc")"

  "$DENV_BIN" -n "$tmp" >/dev/null 2>&1
  local second_run
  second_run="$(cat "${tmp}/.envrc")"

  assert_eq "$first_run" "$second_run" "Second run without --force must not mutate .envrc"
}

test_force_preserves_custom_settings() {
  local tmp="$1"
  local envrc="${tmp}/.envrc"

  "$DENV_BIN" -n "$tmp" >/dev/null 2>&1

  # Add custom user configurations outside the denv block
  printf '\n# Custom Project Setting\nexport CUSTOM_API_KEY="secret-1234"\n' >> "$envrc"

  # Run again with --force
  "$DENV_BIN" -n -f "$tmp" >/dev/null 2>&1

  local content
  content="$(cat "$envrc")"
  assert_contains "$content" 'export CUSTOM_API_KEY="secret-1234"' "Custom configuration must be preserved"
  assert_contains "$content" "# >>> denv initialize >>>" "Denv sentinel block preserved"
}

test_git_exclude_registration() {
  local tmp="$1"
  git init "$tmp" >/dev/null 2>&1

  "$DENV_BIN" -n -g "$tmp" >/dev/null 2>&1

  local exclude_file="${tmp}/.git/info/exclude"
  [[ -f "$exclude_file" ]] || { echo "Git exclude file not created"; return 1; }

  local content
  content="$(cat "$exclude_file")"
  assert_contains "$content" ".envrc" "Git exclude must contain .envrc"
  assert_contains "$content" ".venv/" "Git exclude must contain .venv/"
  assert_contains "$content" ".denv.lock/" "Git exclude must contain .denv.lock/"
}

test_mutex_locking_collision() {
  local tmp="$1"
  local lock_dir="${tmp}/.denv.lock"
  mkdir "$lock_dir"
  # Write current process PID (alive)
  printf '%s\n' "$$" > "${lock_dir}/pid"

  local exit_code=0
  "$DENV_BIN" -n "$tmp" >/dev/null 2>&1 || exit_code=$?
  assert_eq "1" "$exit_code" "Active lock must cause exit with EX_ERR (1)"
}

test_stale_lock_recovery() {
  local tmp="$1"
  local lock_dir="${tmp}/.denv.lock"
  mkdir "$lock_dir"
  # Write a dead PID
  printf '999999\n' > "${lock_dir}/pid"

  local exit_code=0
  "$DENV_BIN" -n "$tmp" >/dev/null 2>&1 || exit_code=$?
  assert_eq "0" "$exit_code" "Stale lock must be cleanly purged and succeed"
  [[ -f "${tmp}/.envrc" ]] || { echo ".envrc was not created after stale lock recovery"; return 1; }
}

test_no_color_compliance() {
  local tmp="$1"
  local out
  out="$("$DENV_BIN" --no-color -h)"
  if [[ "$out" == *$'\033'* ]]; then
    echo "ANSI escape sequences found in --no-color output"
    return 1
  fi
}

test_path_with_spaces() {
  local tmp="$1"
  local space_dir="${tmp}/path with spaces"
  mkdir -p "$space_dir"

  local exit_code=0
  "$DENV_BIN" -n "$space_dir" >/dev/null 2>&1 || exit_code=$?
  assert_eq "0" "$exit_code" "Directory with spaces must be handled safely on initial creation"
  [[ -f "${space_dir}/.envrc" ]] || { echo ".envrc not created in folder with spaces"; return 1; }

  local content
  content="$(cat "${space_dir}/.envrc")"
  assert_contains "$content" "path\\ with\\ spaces" "Space in path must be safely shell-escaped"

  # Test --force to ensure Awk does not strip backslashes
  "$DENV_BIN" -n -f "$space_dir" >/dev/null 2>&1 || exit_code=$?
  assert_eq "0" "$exit_code" "Directory with spaces must be handled safely on --force update"

  local forced_content
  forced_content="$(cat "${space_dir}/.envrc")"
  assert_contains "$forced_content" "path\\ with\\ spaces" "Backslash escaping must survive --force Awk replacement"
}

test_status_command() {
  local tmp="$1"
  local exit_code=0

  # Unconfigured directory: status -q must exit 1
  "$DENV_BIN" status -q "$tmp" >/dev/null 2>&1 || exit_code=$?
  assert_eq "1" "$exit_code" "Status quiet mode must return 1 on unconfigured workspace"

  # Initialize directory
  "$DENV_BIN" -n "$tmp" >/dev/null 2>&1

  # Configured directory: status -q must exit 0
  exit_code=0
  "$DENV_BIN" status -q "$tmp" >/dev/null 2>&1 || exit_code=$?
  assert_eq "0" "$exit_code" "Status quiet mode must return 0 on configured workspace"

  # Add empty .env file and check human-readable status output
  touch "${tmp}/.env"
  local out
  out="$("$DENV_BIN" status "$tmp")"
  assert_contains "$out" ".env:                present (0 variables)" "Empty .env must report 0 variables cleanly"
  if [[ "$out" == *"(0"$'\n'*"0 variables"* ]]; then
    printf 'Duplicate 0\\n0 newline glitch detected in .env variable count\n'
    return 1
  fi
}

test_clean_command() {
  local tmp="$1"
  local envrc="${tmp}/.envrc"

  # Initialize and append custom user setting
  "$DENV_BIN" -n "$tmp" >/dev/null 2>&1
  printf '\nexport USER_SECRET="xyz"\n' >> "$envrc"

  # Clean denv integration
  local exit_code=0
  "$DENV_BIN" clean "$tmp" >/dev/null 2>&1 || exit_code=$?
  assert_eq "0" "$exit_code" "Clean command must exit successfully (0)"

  # Check that custom content is preserved and denv block removed
  local content
  content="$(cat "$envrc")"
  assert_contains "$content" 'export USER_SECRET="xyz"' "Clean must preserve custom configuration"
  if [[ "$content" == *"# >>> denv initialize >>>"* ]]; then
    echo "Denv block was not removed from .envrc during clean"
    return 1
  fi

  # Now status -q must report unconfigured (1)
  exit_code=0
  "$DENV_BIN" status -q "$tmp" >/dev/null 2>&1 || exit_code=$?
  assert_eq "1" "$exit_code" "Status must report unconfigured after clean"
}

test_symlink_rejection() {
  local tmp="$1"
  local real_file="${tmp}/real_file"
  local symlink_file="${tmp}/.envrc"
  touch "$real_file"
  ln -s "$real_file" "$symlink_file"

  local exit_code=0
  "$DENV_BIN" -n "$tmp" >/dev/null 2>&1 || exit_code=$?
  assert_eq "77" "$exit_code" "Operating on a symlinked .envrc must exit with EX_NO_PERM (77)"
}

test_subcommand_version_flags() {
  local tmp="$1"
  local out

  out="$("$DENV_BIN" init -v)"
  assert_contains "$out" "denv version 1." "denv init -v must return version"

  out="$("$DENV_BIN" status --version)"
  assert_contains "$out" "denv version 1." "denv status --version must return version"

  out="$("$DENV_BIN" clean -v)"
  assert_contains "$out" "denv version 1." "denv clean -v must return version"
}

test_bash_completion_syntax() {
  local tmp="$1"
  local comp_file="${SCRIPT_DIR}/completions/bash/denv"
  [[ -s "$comp_file" ]] || { echo "Bash completion file is missing or empty"; return 1; }
  bash -n "$comp_file" || { echo "Bash completion file contains syntax errors"; return 1; }
}

test_flag_injection_defense() {
  local tmp="$1"
  # Place malicious python version flag
  printf -- '--malicious-flag-injection\n' > "${tmp}/.python-version"

  local exit_code=0
  # Backend venv
  "$DENV_BIN" -b venv -n "$tmp" >/dev/null 2>&1 || exit_code=$?
  assert_eq "0" "$exit_code" "Malicious version flag should be ignored without failing"

  local content
  content="$(cat "${tmp}/.envrc")"
  if [[ "$content" == *"--malicious"* ]]; then
    echo "Malicious flag leaked into activation snippet"
    return 1
  fi
}

test_backend_detection_lockfiles() {
  local tmp="$1"
  local out

  # 1. uv.lock
  touch "${tmp}/uv.lock"
  out="$("$DENV_BIN" status "$tmp")"
  assert_contains "$out" "uv" "Status must detect uv"
  assert_contains "$out" "uv.lock" "Source must be uv.lock"
  rm -f "${tmp}/uv.lock"

  # 2. poetry.lock
  touch "${tmp}/poetry.lock"
  out="$("$DENV_BIN" status "$tmp")"
  assert_contains "$out" "poetry" "Status must detect poetry"
  assert_contains "$out" "poetry.lock" "Source must be poetry.lock"
  rm -f "${tmp}/poetry.lock"

  # 3. Pipfile
  touch "${tmp}/Pipfile"
  out="$("$DENV_BIN" status "$tmp")"
  assert_contains "$out" "pipenv" "Status must detect pipenv"
  assert_contains "$out" "Pipfile" "Source must be Pipfile"
  rm -f "${tmp}/Pipfile"

  # 4. pdm.lock
  touch "${tmp}/pdm.lock"
  out="$("$DENV_BIN" status "$tmp")"
  assert_contains "$out" "pdm" "Status must detect pdm"
  assert_contains "$out" "pdm.lock" "Source must be pdm.lock"
  rm -f "${tmp}/pdm.lock"

  # 5. pixi.toml
  touch "${tmp}/pixi.toml"
  out="$("$DENV_BIN" status "$tmp")"
  assert_contains "$out" "pixi" "Status must detect pixi"
  assert_contains "$out" "pixi.toml" "Source must be pixi.toml"
  rm -f "${tmp}/pixi.toml"

  # 6. hatch.toml
  touch "${tmp}/hatch.toml"
  out="$("$DENV_BIN" status "$tmp")"
  assert_contains "$out" "hatch" "Status must detect hatch"
  assert_contains "$out" "hatch.toml" "Source must be hatch.toml"
  rm -f "${tmp}/hatch.toml"

  # 7. environment.yml
  cat <<'YAML' > "${tmp}/environment.yml"
name: my-science-env
channels:
  - conda-forge
YAML
  out="$("$DENV_BIN" status "$tmp")"
  assert_contains "$out" "conda" "Status must detect conda"
  assert_contains "$out" "environment.yml" "Source must be environment.yml"
  rm -f "${tmp}/environment.yml"
}

test_backend_detection_pyproject() {
  local tmp="$1"
  local out

  # Poetry in pyproject.toml
  cat <<'TOML' > "${tmp}/pyproject.toml"
[tool.poetry]
name = "sample-poetry"
version = "0.1.0"
TOML
  out="$("$DENV_BIN" status "$tmp")"
  assert_contains "$out" "poetry" "pyproject tool.poetry must be detected"
  assert_contains "$out" "pyproject.toml" "Source must be pyproject.toml"

  # PDM in pyproject.toml
  cat <<'TOML' > "${tmp}/pyproject.toml"
[tool.pdm]
version = { source = "scm" }
TOML
  out="$("$DENV_BIN" status "$tmp")"
  assert_contains "$out" "pdm" "pyproject tool.pdm must be detected"

  # Hatch in pyproject.toml
  cat <<'TOML' > "${tmp}/pyproject.toml"
[tool.hatch.version]
path = "src/__about__.py"
TOML
  out="$("$DENV_BIN" status "$tmp")"
  assert_contains "$out" "hatch" "pyproject tool.hatch must be detected"
}

test_python_version_resolution() {
  local tmp="$1"
  printf '3.12.2\n' > "${tmp}/.python-version"
  local out
  out="$("$DENV_BIN" status "$tmp")"
  assert_contains "$out" "Python version:      3.12.2" "Status must display valid .python-version"
}

test_clean_deletes_entire_unmodified_envrc() {
  local tmp="$1"
  local envrc="${tmp}/.envrc"

  # Bootstrap fresh envrc
  "$DENV_BIN" -n "$tmp" >/dev/null 2>&1
  [[ -f "$envrc" ]] || { echo ".envrc was not created"; return 1; }

  # Clean without any custom user settings added
  "$DENV_BIN" clean "$tmp" >/dev/null 2>&1
  if [[ -e "$envrc" ]]; then
    echo ".envrc should be completely deleted when only managed denv block existed"
    return 1
  fi
}

# --- Main Suite Runner ---

main() {
  printf '\n%sRunning denv integration test suite...%s\n\n' "$c_bold" "$c_reset"

  run_test test_help_and_version
  run_test test_invalid_flag
  run_test test_fresh_envrc_creation
  run_test test_idempotency_without_force
  run_test test_force_preserves_custom_settings
  run_test test_git_exclude_registration
  run_test test_mutex_locking_collision
  run_test test_stale_lock_recovery
  run_test test_no_color_compliance
  run_test test_path_with_spaces
  run_test test_status_command
  run_test test_clean_command
  run_test test_symlink_rejection
  run_test test_subcommand_version_flags
  run_test test_bash_completion_syntax
  run_test test_flag_injection_defense
  run_test test_backend_detection_lockfiles
  run_test test_backend_detection_pyproject
  run_test test_python_version_resolution
  run_test test_clean_deletes_entire_unmodified_envrc

  printf '\n--------------------------------------------------\n'
  printf 'Results: %d total, %s%d passed%s, %s%d failed%s.\n\n' \
    "$tests_run" \
    "$c_green" "$tests_passed" "$c_reset" \
    "$([ "$tests_failed" -gt 0 ] && echo "$c_red" || echo "$c_green")" "$tests_failed" "$c_reset"

  if [[ "$tests_failed" -gt 0 ]]; then
    exit 1
  fi
}

main "$@"

