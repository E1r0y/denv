#!/usr/bin/env bash
# shellcheck disable=SC2016
#
# install.sh - Production-grade installer for denv
#
# Usage:
#   ./install.sh [OPTIONS]
#   curl -fsSL https://raw.githubusercontent.com/E1r0y/denv/main/install.sh | bash
#

set -Eeuo pipefail

readonly INSTALLER_VERSION="1.3.0"
readonly SCRIPT_NAME="denv"
readonly REPO_DEFAULT="E1r0y/denv"
readonly RAW_BASE_URL="https://raw.githubusercontent.com/${DENV_REPO:-$REPO_DEFAULT}/main"

# Exit codes
readonly EX_OK=0
readonly EX_ERR=1
readonly EX_USAGE=2
readonly EX_NO_PERM=77

# Colors & text styling
use_color=false
b=""
r=""

init_colors() {
  if [[ "$use_color" == true ]]; then
    b=$'\033[1m'
    r=$'\033[0m'
  else
    b=""
    r=""
  fi
}

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]] && [[ "${TERM:-}" != "dumb" ]]; then
  use_color=true
fi
init_colors

log_info() {
  if [[ "$use_color" == true ]]; then
    printf '\033[34m[INFO]\033[0m  %s\n' "$*"
  else
    printf '[INFO]  %s\n' "$*"
  fi
}

log_success() {
  if [[ "$use_color" == true ]]; then
    printf '\033[32m[OK]\033[0m    %s\n' "$*"
  else
    printf '[OK]    %s\n' "$*"
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
    -f, --force           Overwrite existing installation without prompt
        --no-color        Disable ANSI color output
    -h, --help            Print this help message and exit
    -v, --version         Print installer version and exit

DEFAULTS:
    User install (non-root): ~/.local/bin
    Root install:            /usr/local/bin
EOF
}

detect_default_bin_dir() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    printf '/usr/local/bin\n'
  else
    printf '%s/.local/bin\n' "$HOME"
  fi
}

detect_shell_rc() {
  local user_shell
  user_shell="$(basename "${SHELL:-/bin/bash}")"
  case "$user_shell" in
    zsh)
      printf '%s/.zshrc\n' "$HOME"
      ;;
    fish)
      printf '%s/.config/fish/config.fish\n' "$HOME"
      ;;
    bash|*)
      if [[ -f "$HOME/.bashrc" ]]; then
        printf '%s/.bashrc\n' "$HOME"
      elif [[ -f "$HOME/.bash_profile" ]]; then
        printf '%s/.bash_profile\n' "$HOME"
      else
        printf '%s/.profile\n' "$HOME"
      fi
      ;;
  esac
}

check_prerequisites() {
  # 1. Check Bash version >= 3.2
  local bash_major="${BASH_VERSINFO[0]:-0}"
  local bash_minor="${BASH_VERSINFO[1]:-0}"
  if [[ "$bash_major" -lt 3 ]] || { [[ "$bash_major" -eq 3 ]] && [[ "$bash_minor" -lt 2 ]]; }; then
    log_error "denv requires Bash version 3.2 or higher (current: ${BASH_VERSION})."
    exit "$EX_ERR"
  fi

  # 2. Check direnv
  if command -v direnv >/dev/null 2>&1; then
    local direnv_ver
    direnv_ver="$(direnv version 2>/dev/null || echo "unknown")"
    log_success "Found direnv (v${direnv_ver})."
  else
    log_warn "direnv is not installed or not in PATH."
    log_warn "Please install direnv to use denv: https://direnv.net/docs/installation.html"
  fi
}

check_direnv_hook() {
  local user_shell
  user_shell="$(basename "${SHELL:-/bin/bash}")"
  local rc_file
  rc_file="$(detect_shell_rc)"

  if [[ -f "$rc_file" ]]; then
    if grep -Eq 'direnv[[:space:]]+hook' "$rc_file" 2>/dev/null; then
      return 0
    fi
  fi

  log_warn "direnv hook was not detected in '${rc_file}'."
  log_info "Make sure to add the following line to your '${rc_file}':"
  case "$user_shell" in
    zsh)
      printf '    %seval "$(direnv hook zsh)"%s\n' "$b" "$r"
      ;;
    fish)
      printf '    %sdirenv hook fish | source%s\n' "$b" "$r"
      ;;
    *)
      printf '    %seval "$(direnv hook bash)"%s\n' "$b" "$r"
      ;;
  esac
}

find_local_source() {
  local script_dir
  script_dir="$( (cd -P -- "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P) || true )"

  if [[ -n "$script_dir" ]] && [[ -f "${script_dir}/bin/denv" ]]; then
    printf '%s/bin/denv\n' "$script_dir"
    return 0
  fi

  if [[ -f "./bin/denv" ]]; then
    printf '%s/bin/denv\n' "$(pwd -P)"
    return 0
  fi

  return 1
}

install_completions() {
  local base_dir="$1"
  local is_symlink="$2"
  local is_remote="${3:-false}"
  local prefix="${4:-}"

  local bash_dir="$HOME/.local/share/bash-completion/completions"
  local zsh_dir="$HOME/.local/share/zsh/site-functions"
  local fish_dir="$HOME/.config/fish/completions"

  if [[ -n "$prefix" ]]; then
    bash_dir="${prefix%/}/share/bash-completion/completions"
    zsh_dir="${prefix%/}/share/zsh/site-functions"
    fish_dir="${prefix%/}/share/fish/vendor_completions.d"
  elif [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    bash_dir="/usr/local/share/bash-completion/completions"
    zsh_dir="/usr/local/share/zsh/site-functions"
    fish_dir="/usr/local/share/fish/vendor_completions.d"
  fi

  mkdir -p "$bash_dir" "$zsh_dir" "$fish_dir" 2>/dev/null || return 0

  if [[ "$is_remote" == true ]]; then
    local c_base="${RAW_BASE_URL}/completions"
    log_info "Downloading shell completions..."
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "${c_base}/bash/denv" -o "${bash_dir}/denv" 2>/dev/null || true
      curl -fsSL "${c_base}/zsh/_denv" -o "${zsh_dir}/_denv" 2>/dev/null || true
      curl -fsSL "${c_base}/fish/denv.fish" -o "${fish_dir}/denv.fish" 2>/dev/null || true
    elif command -v wget >/dev/null 2>&1; then
      wget -qO "${bash_dir}/denv" "${c_base}/bash/denv" 2>/dev/null || true
      wget -qO "${zsh_dir}/_denv" "${c_base}/zsh/_denv" 2>/dev/null || true
      wget -qO "${fish_dir}/denv.fish" "${c_base}/fish/denv.fish" 2>/dev/null || true
    fi
  elif [[ "$is_symlink" == true ]]; then
    ln -sf "${base_dir}/completions/bash/denv" "${bash_dir}/denv" 2>/dev/null || true
    ln -sf "${base_dir}/completions/zsh/_denv" "${zsh_dir}/_denv" 2>/dev/null || true
    ln -sf "${base_dir}/completions/fish/denv.fish" "${fish_dir}/denv.fish" 2>/dev/null || true
  else
    install -m 0644 "${base_dir}/completions/bash/denv" "${bash_dir}/denv" 2>/dev/null || true
    install -m 0644 "${base_dir}/completions/zsh/_denv" "${zsh_dir}/_denv" 2>/dev/null || true
    install -m 0644 "${base_dir}/completions/fish/denv.fish" "${fish_dir}/denv.fish" 2>/dev/null || true
  fi
  log_success "Shell completions registered (Bash, Zsh, Fish)."
}

do_uninstall() {
  local bin_dir="$1"
  local prefix="${2:-}"
  local target="${bin_dir}/${SCRIPT_NAME}"

  if [[ -f "$target" ]] || [[ -L "$target" ]]; then
    rm -f -- "$target"
    log_success "Successfully removed '${target}'."
  else
    log_warn "Executable '${target}' was not found."
  fi

  # Clean up completions across candidate directories
  local bash_candidates=(
    "$HOME/.local/share/bash-completion/completions/denv"
    "/usr/local/share/bash-completion/completions/denv"
  )
  local zsh_candidates=(
    "$HOME/.local/share/zsh/site-functions/_denv"
    "/usr/local/share/zsh/site-functions/_denv"
  )
  local fish_candidates=(
    "$HOME/.config/fish/completions/denv.fish"
    "/usr/local/share/fish/vendor_completions.d/denv.fish"
  )

  if [[ -n "$prefix" ]]; then
    bash_candidates+=("${prefix%/}/share/bash-completion/completions/denv")
    zsh_candidates+=("${prefix%/}/share/zsh/site-functions/_denv")
    fish_candidates+=("${prefix%/}/share/fish/vendor_completions.d/denv.fish")
  fi

  local f
  for f in "${bash_candidates[@]}" "${zsh_candidates[@]}" "${fish_candidates[@]}"; do
    rm -f -- "$f" 2>/dev/null || true
  done

  exit "$EX_OK"
}

main() {
  local symlink_mode=false
  local force_mode=false
  local uninstall_mode=false
  local custom_bin_dir=""
  local prefix_dir=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -s|--symlink)
        symlink_mode=true
        shift
        ;;
      -b|--bin-dir)
        [[ $# -lt 2 ]] && { log_error "Option '$1' requires an argument."; exit "$EX_USAGE"; }
        custom_bin_dir="$2"
        shift 2
        ;;
      -p|--prefix)
        [[ $# -lt 2 ]] && { log_error "Option '$1' requires an argument."; exit "$EX_USAGE"; }
        prefix_dir="$2"
        shift 2
        ;;
      -u|--uninstall)
        uninstall_mode=true
        shift
        ;;
      -f|--force)
        force_mode=true
        shift
        ;;
      --no-color)
        use_color=false
        init_colors
        shift
        ;;
      -h|--help)
        usage
        exit "$EX_OK"
        ;;
      -v|--version)
        printf 'denv installer version %s\n' "$INSTALLER_VERSION"
        exit "$EX_OK"
        ;;
      *)
        log_error "Unknown option: $1"
        usage >&2
        exit "$EX_USAGE"
        ;;
    esac
  done

  # Determine target bin directory
  local bin_dir=""
  if [[ -n "$custom_bin_dir" ]]; then
    bin_dir="$custom_bin_dir"
  elif [[ -n "$prefix_dir" ]]; then
    bin_dir="${prefix_dir%/}/bin"
  else
    bin_dir="$(detect_default_bin_dir)"
  fi

  if [[ "$uninstall_mode" == true ]]; then
    do_uninstall "$bin_dir" "$prefix_dir"
  fi

  check_prerequisites

  # Locate source file
  local local_source=""
  if local_source="$(find_local_source)"; then
    log_info "Found local source binary at '${local_source}'."
  else
    if [[ "$symlink_mode" == true ]]; then
      log_error "Cannot use --symlink when running from a remote pipeline (no local repo found)."
      exit "$EX_USAGE"
    fi
  fi

  # Create destination directory safely
  if [[ ! -d "$bin_dir" ]]; then
    log_info "Creating destination directory '${bin_dir}'..."
    mkdir -p -- "$bin_dir" 2>/dev/null || {
      log_error "Failed to create directory '${bin_dir}'. Permission denied."
      exit "$EX_NO_PERM"
    }
  fi

  if [[ ! -w "$bin_dir" ]]; then
    log_error "Destination directory '${bin_dir}' is not writable."
    exit "$EX_NO_PERM"
  fi

  local destination="${bin_dir}/${SCRIPT_NAME}"

  if [[ -e "$destination" ]] || [[ -L "$destination" ]]; then
    if [[ "$force_mode" == false ]]; then
      log_warn "Existing file found at '${destination}'. Overwriting."
    fi
    rm -f -- "$destination"
  fi

  if [[ "$symlink_mode" == true ]]; then
    ln -sf -- "$local_source" "$destination"
    log_success "Symlinked '${local_source}' -> '${destination}'."
  else
    if [[ -n "$local_source" ]]; then
      install -m 0755 -- "$local_source" "$destination"
    else
      # Remote download via curl or wget
      local remote_url="${RAW_BASE_URL}/bin/denv"
      log_info "Downloading denv from '${remote_url}'..."

      local temp_dl
      temp_dl="$(mktemp "${bin_dir}/.denv.dl.XXXXXXXXXX")"

      if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$remote_url" -o "$temp_dl"
      elif command -v wget >/dev/null 2>&1; then
        wget -qO "$temp_dl" "$remote_url"
      else
        rm -f -- "$temp_dl"
        log_error "Neither 'curl' nor 'wget' is available for remote download."
        exit "$EX_ERR"
      fi

      chmod 0755 "$temp_dl"
      mv -f -- "$temp_dl" "$destination"
    fi
    log_success "Installed '${SCRIPT_NAME}' executable to '${destination}'."
  fi

  if [[ -n "$local_source" ]]; then
    local repo_root
    repo_root="$(cd -P -- "$(dirname "$local_source")/.." && pwd -P)"
    install_completions "$repo_root" "$symlink_mode" false "$prefix_dir"
  else
    install_completions "" false true "$prefix_dir"
  fi

  # Verify PATH presence
  case ":$PATH:" in
    *":${bin_dir}:"*)
      log_success "'${bin_dir}' is already present in your \$PATH."
      ;;
    *)
      local rc_file
      rc_file="$(detect_shell_rc)"
      log_warn "'${bin_dir}' is NOT found in your current \$PATH."
      log_info "Add it to your environment by appending this line to '${rc_file}':"
      printf '    %sexport PATH="%s:$PATH"%s\n\n' "$b" "$bin_dir" "$r"
      ;;
  esac

  check_direnv_hook

  printf '\n'
  log_success "Installation complete! Run 'denv --help' to get started."
}

main "$@"

