#!/usr/bin/env bash
# shellcheck disable=SC2016
#
# install.sh - Atomic installer for denv
#
# Usage:
#   ./install.sh [OPTIONS]
#   curl -fsSL https://raw.githubusercontent.com/E1r0y/denv/main/install.sh | bash
#

set -Eeuo pipefail

readonly INSTALLER_VERSION="1.4.0"
readonly REPO_DEFAULT="E1r0y/denv"

# Exit codes
readonly EX_ERR=1
readonly EX_USAGE=2
readonly EX_NO_PERM=77

# Colors & text styling
use_color=false

if [[ -t 2 ]] && [[ -z "${NO_COLOR:-}" ]] && [[ "${TERM:-}" != "dumb" ]]; then
  use_color=true
fi

log_info() {
  if [[ "$use_color" == true ]]; then
    printf '\033[34m[INFO]\033[0m  %s\n' "$*" >&2
  else
    printf '[INFO]  %s\n' "$*" >&2
  fi
}

log_success() {
  if [[ "$use_color" == true ]]; then
    printf '\033[32m[OK]\033[0m    %s\n' "$*" >&2
  else
    printf '[OK]    %s\n' "$*" >&2
  fi
}

log_warn() {
  if [[ "$use_color" == true ]]; then
    printf '\033[33m[WARN]\033[0m  %s\n' "$*" >&2
  else
    printf '[WARN]  %s\n' "$*" >&2
  fi
}

log_error() {
  if [[ "$use_color" == true ]]; then
    printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2
  else
    printf '[ERROR] %s\n' "$*" >&2
  fi
}

usage() {
  cat <<EOF
denv installer v${INSTALLER_VERSION}

USAGE:
    install.sh [OPTIONS]

OPTIONS:
    -s, --symlink         Create a symlink to bin/denv instead of copying (requires local repo)
    -b, --bin-dir <DIR>   Custom directory to install the executable (e.g. ~/.local/bin)
    -p, --prefix <DIR>    Install prefix directory (executable placed in <PREFIX>/bin)
    -u, --uninstall       Remove denv from the target directory
    -f, --force           Replace an existing installation (required for updates)
        --ref <REF>       Install a remote tag or commit (DENV_REF; default: main)
        --no-color        Disable ANSI color output
    -h, --help            Print this help message and exit
    -v, --version         Print installer version and exit

DEFAULTS:
    User install (non-root): ~/.local/bin
    Root install:            /usr/local/bin
EOF
}

temp_file=""
stage_dir=""

cleanup() {
  if [[ -n "$temp_file" ]]; then rm -f -- "$temp_file"; fi
  if [[ -n "$stage_dir" ]]; then rm -rf -- "$stage_dir"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else log_error "SHA256 verification requires sha256sum or shasum."; return 1; fi
}

download() {
  local url="$1" output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 2 --connect-timeout 10 --max-time 60 "$url" -o "$output"
  elif command -v wget >/dev/null 2>&1; then
    wget --timeout=60 --tries=3 -qO "$output" "$url"
  else log_error "Remote installation requires curl or wget."; return 1; fi
}

find_local_source() {
  local source_file="${BASH_SOURCE[0]:-}" script_dir
  [[ -n "$source_file" && -f "$source_file" ]] || return 1
  script_dir="$(cd -P -- "$(dirname -- "$source_file")" && pwd -P)" || return 1
  [[ -f "${script_dir}/bin/denv" ]] || return 1
  printf '%s\n' "$script_dir"
}

prepare_remote_source() {
  local repo="${DENV_REPO:-$REPO_DEFAULT}" ref="$1" commit relative expected actual
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && "$ref" =~ ^[A-Za-z0-9_./-]+$ ]] || {
    log_error "Invalid repository or Git ref."; return 1;
  }
  if [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then commit="$ref"
  else
    download "https://api.github.com/repos/${repo}/commits/${ref}" "$stage_dir/commit.json" || return 1
    commit="$(sed -n '/^[[:space:]]*"sha":/ { s/^[[:space:]]*"sha":[[:space:]]*"\([0-9a-f]*\)".*/\1/; p; q; }' "$stage_dir/commit.json")" || return 1
    [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { log_error "Could not resolve '${ref}' to a commit."; return 1; }
  fi
  local base_url="https://raw.githubusercontent.com/${repo}/${commit}"
  log_info "Downloading verified sources at ${repo}@${commit}."
  download "${base_url}/checksums.sha256" "$stage_dir/checksums.sha256" || return 1
  for relative in bin/denv completions/bash/denv completions/zsh/_denv completions/fish/denv.fish; do
    mkdir -p -- "$stage_dir/$(dirname -- "$relative")" || return 1
    download "${base_url}/${relative}" "$stage_dir/$relative" || return 1
    expected="$(awk -v file="$relative" '$2 == file { value=$1; count++ } END { if (count != 1) exit 1; print value }' "$stage_dir/checksums.sha256")" || return 1
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || { log_error "Invalid checksum for '${relative}'."; return 1; }
    actual="$(sha256_file "$stage_dir/$relative")" || return 1
    [[ "$actual" == "$expected" ]] || { log_error "SHA256 mismatch for '${relative}'; installation left unchanged."; return 1; }
  done
}

# Every destination is replaced only after its complete replacement exists.
# This also replaces an old symlink without following it and writing its target.
atomic_install() {
  local source="$1" destination="$2" mode="$3" symlink="$4" parent
  # A previous optional completion write may have failed. Remove its staged
  # file before tracking a new one; EXIT handles the last failed write.
  if [[ -n "$temp_file" ]]; then
    rm -f -- "$temp_file" || return 1
    temp_file=""
  fi
  parent="$(dirname -- "$destination")" || return 1
  [[ ! -d "$destination" ]] || { log_error "Destination is a directory: '${destination}'."; return 1; }
  mkdir -p -- "$parent" || return 1
  temp_file="$(mktemp "${parent}/.denv.tmp.XXXXXXXX")" || return 1
  if [[ "$symlink" == true ]]; then
    rm -f -- "$temp_file" || return 1
    ln -s -- "$source" "$temp_file" || return 1
  else
    cat -- "$source" >"$temp_file" || return 1
    chmod "$mode" "$temp_file" || return 1
  fi
  mv -f -- "$temp_file" "$destination" || return 1
  temp_file=""
}

set_completion_directories() {
  local prefix="$1"
  if [[ -n "$prefix" ]]; then
    bash_dir="${prefix%/}/share/bash-completion/completions"
    zsh_dir="${prefix%/}/share/zsh/site-functions"
    fish_dir="${prefix%/}/share/fish/vendor_completions.d"
  elif [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    bash_dir=/usr/local/share/bash-completion/completions
    zsh_dir=/usr/local/share/zsh/site-functions
    fish_dir=/usr/local/share/fish/vendor_completions.d
  else
    bash_dir="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"
    zsh_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
    fish_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fish/completions"
  fi
}

install_completions() {
  local source="$1" symlink="$2" failed=false
  if ! atomic_install "$source/completions/bash/denv" "$bash_dir/denv" 0644 "$symlink"; then failed=true; fi
  if ! atomic_install "$source/completions/zsh/_denv" "$zsh_dir/_denv" 0644 "$symlink"; then failed=true; fi
  if ! atomic_install "$source/completions/fish/denv.fish" "$fish_dir/denv.fish" 0644 "$symlink"; then failed=true; fi
  if [[ "$failed" == true ]]; then
    log_warn "Some shell completions could not be installed. Check destination permissions."
    return 1
  fi
  log_success "Installed Bash, Zsh and Fish completion files."
}

detect_shell_rc() {
  local user_shell="${SHELL:-/bin/bash}" zdotdir="${ZDOTDIR:-}" line value
  user_shell="${user_shell##*/}"
  case "$user_shell" in
    zsh)
      if [[ -z "$zdotdir" && -f "$HOME/.zshenv" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
          if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?ZDOTDIR=(.*)$ ]]; then
            value="${BASH_REMATCH[2]}"
            case "$value" in
              \"*) value="${value#\"}"; value="${value%%\"*}" ;;
              \'*) value="${value#\'}"; value="${value%%\'*}" ;;
              *) value="${value%%[[:space:]]*}" ;;
            esac
            value="${value//\$\{HOME\}/$HOME}"
            value="${value//\$HOME/$HOME}"
            if [[ "$value" == \~/* ]]; then value="$HOME/${value#\~/}"; fi
            if [[ "$value" == /* && "$value" != *'$'* ]]; then zdotdir="$value"; fi
            break
          fi
        done <"$HOME/.zshenv"
      fi
      if [[ -n "$zdotdir" ]]; then printf '%s/.zshrc\n' "$zdotdir"
      elif [[ -f "$HOME/.zshrc" ]]; then printf '%s/.zshrc\n' "$HOME"
      elif [[ -f "$HOME/.config/zsh/.zshrc" ]]; then printf '%s/.config/zsh/.zshrc\n' "$HOME"
      else printf '%s/.zshrc\n' "$HOME"; fi ;;
    fish) printf '%s/fish/config.fish\n' "${XDG_CONFIG_HOME:-$HOME/.config}" ;;
    *)
      if [[ -f "$HOME/.bashrc" ]]; then printf '%s/.bashrc\n' "$HOME"
      elif [[ -f "$HOME/.bash_profile" ]]; then printf '%s/.bash_profile\n' "$HOME"
      else printf '%s/.profile\n' "$HOME"; fi ;;
  esac
}

show_shell_setup() {
  local bin_dir="$1" user_shell="${SHELL:-/bin/bash}" rc_file safe_dir safe_zsh
  user_shell="${user_shell##*/}"
  rc_file="$(detect_shell_rc)"
  printf -v safe_dir '%q' "$bin_dir"
  printf -v safe_zsh '%q' "$zsh_dir"
  case ":$PATH:" in
    *":${bin_dir}:"*) ;;
    *)
      log_info "Add the executable directory in '${rc_file}':"
      if [[ "$user_shell" == fish ]]; then printf '    fish_add_path %s\n' "$safe_dir" >&2
      else printf '    export PATH=%s:"$PATH"\n' "$safe_dir" >&2; fi ;;
  esac
  local hook_found=false rc_dir
  rc_dir="$(dirname -- "$rc_file")"
  if [[ -f "$rc_file" ]] && grep -Eq '^[[:space:]]*[^#].*direnv[[:space:]]+hook|^[[:space:]]*direnv[[:space:]]+hook' "$rc_file"; then hook_found=true; fi
  if [[ "$user_shell" == zsh && -d "$rc_dir/conf.d" ]] && grep -Eqr '^[[:space:]]*[^#].*direnv[[:space:]]+hook' "$rc_dir/conf.d"; then hook_found=true; fi
  if [[ "$hook_found" == false ]]; then
    log_info "Add the direnv hook in '${rc_file}':"
    case "$user_shell" in
      zsh) printf '    eval "$(direnv hook zsh)"\n' >&2 ;;
      fish) printf '    direnv hook fish | source\n' >&2 ;;
      *) printf '    eval "$(direnv hook bash)"\n' >&2 ;;
    esac
  fi
  if [[ "$user_shell" == zsh ]]; then
    log_info "For Zsh completions, put this before your existing compinit call in '${rc_file}':"
    printf '    fpath=(%s $fpath)\n' "$safe_zsh" >&2
    log_info "Initialize completion with: autoload -Uz compinit; compinit"
  elif [[ "$user_shell" == fish && "$fish_dir" != "${XDG_CONFIG_HOME:-$HOME/.config}/fish/completions" ]]; then
    log_info "For this custom prefix, add to '${rc_file}':"
    printf '    set -p fish_complete_path %q\n' "$fish_dir" >&2
  elif [[ "$user_shell" != fish && "$user_shell" != zsh ]]; then
    log_info "If Bash completion is not loaded automatically, source '${bash_dir}/denv' from '${rc_file}'."
  fi
}

main() {
  local symlink=false force=false uninstall=false bin_dir="" prefix="" ref="${DENV_REF:-main}" remote=false
  [[ -z "${DENV_REF:-}" ]] || remote=true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -s|--symlink) symlink=true; shift ;;
      -f|--force) force=true; shift ;;
      -u|--uninstall) uninstall=true; shift ;;
      -b|--bin-dir|-p|--prefix|--ref)
        [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { log_error "Option '$1' requires an argument."; exit "$EX_USAGE"; }
        case "$1" in
          -b|--bin-dir) bin_dir="$2" ;;
          -p|--prefix) prefix="$2" ;;
          --ref) ref="$2"; remote=true ;;
        esac
        shift 2 ;;
      --no-color) use_color=false; shift ;;
      -h|--help) usage; return 0 ;;
      -v|--version) printf 'denv installer version %s\n' "$INSTALLER_VERSION"; return 0 ;;
      *) log_error "Unknown option: $1"; exit "$EX_USAGE" ;;
    esac
  done
  [[ -z "$bin_dir" || -z "$prefix" ]] || { log_error "Use either --prefix or --bin-dir, not both."; exit "$EX_USAGE"; }
  if [[ -z "$bin_dir" ]]; then
    if [[ -n "$prefix" ]]; then bin_dir="${prefix%/}/bin"
    elif [[ "${EUID:-$(id -u)}" -eq 0 ]]; then bin_dir=/usr/local/bin
    else bin_dir="$HOME/.local/bin"; fi
  fi
  set_completion_directories "$prefix"
  local destination="${bin_dir%/}/denv"
  if [[ "$uninstall" == true ]]; then
    [[ ! -d "$destination" ]] || { log_error "Refusing to remove directory '${destination}'."; exit "$EX_NO_PERM"; }
    rm -f -- "$destination" "$bash_dir/denv" "$zsh_dir/_denv" "$fish_dir/denv.fish"
    log_success "Removed denv and completions from the selected installation scope."
    return 0
  fi
  if [[ -e "$destination" || -L "$destination" ]]; then
    [[ "$force" == true ]] || { log_error "'${destination}' already exists. Use --force to replace it."; exit "$EX_ERR"; }
  fi
  mkdir -p -- "$bin_dir" || { log_error "Cannot create '${bin_dir}'."; exit "$EX_NO_PERM"; }
  bin_dir="$(cd -P -- "$bin_dir" && pwd -P)"
  destination="${bin_dir}/denv"
  [[ -w "$bin_dir" ]] || { log_error "Directory '${bin_dir}' is not writable."; exit "$EX_NO_PERM"; }
  stage_dir="$(mktemp -d "${bin_dir}/.denv.install.XXXXXXXX")"
  local source=""
  if [[ "$remote" == false ]]; then source="$(find_local_source || true)"; fi
  if [[ -z "$source" ]]; then
    [[ "$symlink" == false ]] || { log_error "--symlink requires the local repository."; exit "$EX_USAGE"; }
    prepare_remote_source "$ref"
    source="$stage_dir"
  fi
  [[ "$destination" != "$source/bin/denv" ]] || { log_error "Destination would replace the repository source."; exit "$EX_USAGE"; }
  local relative
  for relative in bin/denv completions/bash/denv completions/zsh/_denv completions/fish/denv.fish; do
    [[ -f "$source/$relative" ]] || { log_error "Source file missing: ${relative}"; exit "$EX_ERR"; }
  done
  bash -n "$source/bin/denv"
  atomic_install "$source/bin/denv" "$destination" 0755 "$symlink"
  local completion_failed=false
  if ! install_completions "$source" "$symlink"; then completion_failed=true; fi
  if ! command -v direnv >/dev/null 2>&1; then log_warn "Install direnv >= 2.26 before using denv."; fi
  show_shell_setup "$bin_dir"
  if [[ "$completion_failed" == true ]]; then
    log_warn "Executable installed, but completion installation was incomplete."
    return 1
  fi
  log_success "Installation complete: '${destination}'."
}

main "$@"
