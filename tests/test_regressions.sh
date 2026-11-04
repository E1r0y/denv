#!/usr/bin/env bash
# Regression tests exercise the CLI with isolated homes and command adapters.
# Each case runs in a subshell with its own XDG directories.
# shellcheck disable=SC2030,SC2031
set -Eeuo pipefail

repo_dir="$(cd -P -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly repo_dir
readonly denv_bin="${repo_dir}/bin/denv"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/denv-regression.XXXXXXXX")"
readonly test_root
trap 'rm -rf -- "$test_root"' EXIT
export NO_COLOR=1
export GIT_CONFIG_GLOBAL=/dev/null
export UV_PYTHON_DOWNLOADS=never
export DENV_ALLOW_ROOT=1
tests_passed=0
tests_failed=0

assert() {
  if ! "$@"; then
    printf 'Assertion failed:' >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
    return 1
  fi
}

expect_exit() {
  local expected="$1" actual=0
  shift
  "$@" >"$case_dir/stdout" 2>"$case_dir/stderr" || actual=$?
  if [[ "$actual" != "$expected" ]]; then
    cat "$case_dir/stdout" "$case_dir/stderr" >&2
    printf 'Expected exit %s, received %s\n' "$expected" "$actual" >&2
    return 1
  fi
}

make_venv() {
  mkdir -p "$1/bin"
  # shellcheck disable=SC2016
  printf 'export VIRTUAL_ENV=%q\nexport PATH=%q/bin:$PATH\n' "$1" "$1" >"$1/bin/activate"
}

make_stub() {
  local name="$1"
  printf '#!/usr/bin/env bash\n' >"$case_dir/tools/$name"
  cat >>"$case_dir/tools/$name"
  chmod +x "$case_dir/tools/$name"
}

run_case() {
  local name="$1" pid
  case_dir="${test_root}/${name}"
  mkdir -p "$case_dir/home" "$case_dir/work" "$case_dir/tools"
  (
    set -Eeuo pipefail
    export HOME="$case_dir/home" SHELL=/bin/bash
    export XDG_CONFIG_HOME="$HOME/config" XDG_CACHE_HOME="$HOME/cache" XDG_DATA_HOME="$HOME/data"
    export DIRENV_CONFIG="$XDG_CONFIG_HOME/direnv" UV_CACHE_DIR="$XDG_CACHE_HOME/uv"
    export PATH="$case_dir/tools:$PATH"
    cd "$case_dir/work"
    "$name"
  ) >"$case_dir/log" 2>&1 &
  pid=$!
  if wait "$pid"; then
    tests_passed=$((tests_passed + 1))
    printf 'PASS %s\n' "$name"
  else
    tests_failed=$((tests_failed + 1))
    printf 'FAIL %s\n' "$name"
    cat "$case_dir/log"
  fi
}

test_malformed_markers_are_preserved() {
  local variant action
  for variant in unclosed orphan duplicate nested; do
    case "$variant" in
      unclosed) printf '# >>> denv initialize >>>\nexport KEEP=yes\n' >.envrc ;;
      orphan) printf '# <<< denv initialize <<<\nexport KEEP=yes\n' >.envrc ;;
      duplicate) printf '# >>> denv initialize >>>\n# <<< denv initialize <<<\n# >>> denv initialize >>>\n# <<< denv initialize <<<\n' >.envrc ;;
      nested) printf '# >>> denv initialize >>>\n# >>> denv initialize >>>\n# <<< denv initialize <<<\n' >.envrc ;;
    esac
    cp .envrc "$case_dir/original"
    for action in init clean; do
      if [[ "$action" == init ]]; then
        expect_exit 1 "$denv_bin" -b venv -n -f .
      else
        expect_exit 1 "$denv_bin" clean .
      fi
      assert cmp .envrc "$case_dir/original"
    done
    expect_exit 1 "$denv_bin" status -q .
  done
}

test_crlf_and_file_modes() {
  printf 'export BEFORE=yes\r\n# >>> denv initialize >>>\r\n# old\r\n# <<< denv initialize <<<\r\nexport AFTER=yes\r\n' >.envrc
  chmod 640 .envrc
  "$denv_bin" -b venv -n -f .
  assert grep -q 'export AFTER=yes' .envrc
  assert grep -q 'dotenv_if_exists .env' .envrc
  "$denv_bin" clean .
  assert grep -q 'export BEFORE=yes' .envrc
  assert grep -q 'export AFTER=yes' .envrc
  assert test "$(wc -l <.envrc | tr -d ' ')" = 2
  local mode
  mode="$(stat -c '%a' .envrc 2>/dev/null || stat -f '%Lp' .envrc)"
  assert test "$mode" = 640
}

test_clean_respects_active_lock() {
  "$denv_bin" -b venv -n .
  cp .envrc "$case_dir/original"
  mkdir .denv.lock
  printf '%s\n' "$$" >.denv.lock/pid
  expect_exit 1 "$denv_bin" clean .
  assert cmp .envrc "$case_dir/original"
  assert test -f .denv.lock/pid
}

test_initializing_lock_is_not_stale() {
  mkdir .denv.lock
  expect_exit 1 "$denv_bin" -b venv -n .
  assert test -d .denv.lock
  assert test ! -e .envrc
}

test_repeat_init_has_no_backend_side_effects() {
  "$denv_bin" -b venv -n .
  make_stub uv <<'STUB'
printf 'backend unexpectedly invoked\n' >&2
exit 99
STUB
  expect_exit 0 "$denv_bin" -b uv .
}

test_old_direnv_is_rejected() {
  make_stub direnv <<'STUB'
printf '2.25.2\n'
STUB
  expect_exit 1 "$denv_bin" -b venv -n .
  assert test ! -e .envrc
}

test_no_create_never_uses_dynamic_layouts() {
  local backend
  for backend in poetry pipenv pdm hatch; do
    make_stub "$backend" <<'STUB'
exit 1
STUB
    expect_exit 1 "$denv_bin" -b "$backend" -n .
    assert test ! -e .envrc
  done
}

test_python_version_is_enforced() {
  printf '0.0.0\n' >.python-version
  expect_exit 1 "$denv_bin" -b venv .
  assert test ! -e .venv
  assert test ! -e .envrc
}

test_manager_paths_must_be_valid() {
  make_stub poetry <<'STUB'
printf '%s\n' "$PWD/nonexistent"
STUB
  expect_exit 1 "$denv_bin" -b poetry .
  assert test ! -e .envrc
}

test_status_checks_readiness_and_authorization() {
  "$denv_bin" -b venv -n .
  expect_exit 1 "$denv_bin" status -q .
  make_venv "$PWD/.venv"
  expect_exit 0 "$denv_bin" status -q .
  direnv deny .
  expect_exit 1 "$denv_bin" status -q .
  direnv allow .
  rm .envrc
  printf '# >>> denv initialize >>>\n' >.envrc
  expect_exit 1 "$denv_bin" status -q .
}

test_bash_completion_preserves_spaces() {
  mkdir -p "$case_dir/path with spaces/complete_target"
  # shellcheck disable=SC1091
  source "$repo_dir/completions/bash/denv"
  COMP_WORDS=(denv init "$case_dir/path with spaces/co")
  COMP_CWORD=2
  _denv_completions
  assert test "${#COMPREPLY[@]}" = 1
  assert test "${COMPREPLY[0]}" = "$case_dir/path with spaces/complete_target"
}

test_make_paths_and_scoped_uninstall() {
  local prefix="$case_dir/install with spaces"
  make -C "$repo_dir" install "PREFIX=$prefix"
  assert test -x "$prefix/bin/denv"
  expect_exit 0 "$prefix/bin/denv" --version
  make -C "$repo_dir" uninstall "PREFIX=$prefix"
  assert test ! -e "$prefix/bin/denv"
}

test_installer_requires_force() {
  mkdir -p "$case_dir/prefix/bin"
  printf 'existing installation\n' >"$case_dir/prefix/bin/denv"
  cp "$case_dir/prefix/bin/denv" "$case_dir/original"
  expect_exit 1 bash "$repo_dir/install.sh" -p "$case_dir/prefix"
  assert cmp "$case_dir/original" "$case_dir/prefix/bin/denv"
}

test_failed_download_preserves_installation() {
  cp "$repo_dir/install.sh" "$case_dir/install.sh"
  mkdir -p "$case_dir/prefix/bin"
  printf 'existing installation\n' >"$case_dir/prefix/bin/denv"
  cp "$case_dir/prefix/bin/denv" "$case_dir/original"
  make_stub curl <<'STUB'
exit 22
STUB
  local result=0
  bash "$case_dir/install.sh" -f -p "$case_dir/prefix" >"$case_dir/stdout" 2>"$case_dir/stderr" || result=$?
  assert test "$result" != 0
  assert cmp "$case_dir/original" "$case_dir/prefix/bin/denv"
  assert test "$(find "$case_dir/prefix/bin" -name '.denv.*' | wc -l | tr -d ' ')" = 0
}

test_uninstall_does_not_touch_other_prefixes() {
  mkdir -p "$XDG_DATA_HOME/bash-completion/completions" "$HOME/.local/share/bash-completion/completions"
  printf 'keep\n' >"$XDG_DATA_HOME/bash-completion/completions/denv"
  printf 'keep\n' >"$HOME/.local/share/bash-completion/completions/denv"
  bash "$repo_dir/install.sh" -u -p "$case_dir/unrelated"
  assert test -f "$XDG_DATA_HOME/bash-completion/completions/denv"
  assert test -f "$HOME/.local/share/bash-completion/completions/denv"
}

for test_name in \
  test_malformed_markers_are_preserved test_crlf_and_file_modes \
  test_clean_respects_active_lock test_initializing_lock_is_not_stale \
  test_repeat_init_has_no_backend_side_effects test_old_direnv_is_rejected \
  test_no_create_never_uses_dynamic_layouts test_python_version_is_enforced \
  test_manager_paths_must_be_valid test_status_checks_readiness_and_authorization \
  test_bash_completion_preserves_spaces test_make_paths_and_scoped_uninstall \
  test_installer_requires_force test_failed_download_preserves_installation \
  test_uninstall_does_not_touch_other_prefixes; do
  run_case "$test_name"
done
printf '\nRegressions: %s passed, %s failed\n' "$tests_passed" "$tests_failed"
[[ "$tests_failed" == 0 ]]
