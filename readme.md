# denv

[![Bash 4.0+](https://img.shields.io/badge/Bash-4.0%2B-blue.svg)](https://www.gnu.org/software/bash/)
[![direnv](https://img.shields.io/badge/direnv-%3E%3D2.21-purple.svg)](https://direnv.net/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**`denv`** is an atomic, lightning-fast CLI workspace bootstrapper that bridges Python package managers (`uv`, `poetry`, `pipenv`, `pdm`, `hatch`, `conda`/`mamba`, `pixi`, standard `venv`) and `.env` files with [`direnv`](https://direnv.net/).

Run `denv` once inside any Python workspace — after that, your virtual environment and environment variables automatically activate whenever you `cd` into the project, and cleanly unload when you leave.

---

## Quick Start

```bash
# 1. Navigate to your Python project
cd ~/projects/my-app

# 2. Bootstrap workspace configuration in one command
denv

# Done! Your virtual environment and .env now automatically load on cd.

# 3. Check workspace configuration status at any time
denv status

# 4. Remove denv integration if needed (preserves your custom .envrc settings and venv)
denv clean
```

---

## Why `denv`? (Ahead-of-Time Path Resolution)

Standard `direnv` integrations (such as `layout poetry`, `layout pipenv`, or `layout uv`) invoke heavy package managers during shell directory switches. Running Python, Poetry, or UV on every single navigation introduces **100–300 ms of terminal latency**, causing noticeable shell lag.

`denv` adopts an **Ahead-of-Time (AoT) Path Resolution** architecture:
1. Queries your package manager **once** at bootstrap.
2. Resolves and safely quotes the exact virtual environment activation path on disk.
3. Writes a pure-shell activation block enclosed in managed sentinels to `.envrc`.
4. Automatically grants permissions via `direnv allow`.

This reduces directory-switch overhead down to **~1–2 ms** (instantaneous native shell execution).

```
Traditional direnv layout:
[cd project] ──> [spawn python/poetry] ──> [query venv] ──> [activate] (150-300ms lag)

denv AoT Architecture:
[denv (run once)] ──> [resolve path] ──> [write optimized .envrc snippet]
[cd project]      ──> [pure-shell source]                              (~1-2ms instant)
```

---

## Key Features

- **Multi-Backend Auto-Detection:** Automatically discovers and configures `uv`, `poetry`, `pipenv`, `pdm`, `hatch`, `conda`/`mamba`, `pixi`, or standard `venv`.
- **Atomic & Non-Destructive:** Writes updates using atomic temp files (`mktemp`) and in-place marker replacement without wiping custom `.envrc` configurations.
- **Enterprise-Grade Mutex Locking:** Enforces atomic directory locks (`.denv.lock`) with automated stale-lock detection and PID verification.
- **Strict Stream Separation:** Status, warnings, and errors flow strictly to `stderr` (`>&2`). Data, versioning, and help output flow to `stdout`.
- **Intelligent TTY & Color Support:** Automatic detection of terminal capabilities, honoring `NO_COLOR` ([no-color.org](https://no-color.org/)), `TERM=dumb`, and `--no-color`.
- **Defensive Shell Security:**
  - Blocks execution as `root` (UID 0) to prevent permission pollution.
  - Refuses to follow symlinked `.envrc` targets.
  - Sanitizes Python version strings against command and flag injection.
  - Safely shell-escapes all file system paths using `printf '%q'`.
  - Cleans up partially initialized virtual environments on `SIGINT` / `SIGTERM` / `SIGHUP` without affecting pre-existing files.
- **Git Hygiene (`--git-exclude`):** Automatically registers `.envrc`, `.envrc.bak`, `.venv/`, and `.denv.lock/` in local `.git/info/exclude` without altering shared `.gitignore` files.

---

## Prerequisites

- **Bash** `>= 4.0`
- **[direnv](https://direnv.net/)** `>= 2.21` (hooked into your interactive shell)
- A Python package manager of your choice (`uv`, `poetry`, `pipenv`, `pdm`, `hatch`, `conda`/`mamba`, `pixi`, or `python3`)

Ensure `direnv` hook is active in your interactive shell (e.g. `~/.bashrc` or `~/.zshrc`):

```bash
# For bash
eval "$(direnv hook bash)"

# For zsh
eval "$(direnv hook zsh)"

# For fish
direnv hook fish | source
```

---

## Installation

### Method 1: Automated One-Line Installer (Recommended)

Install `denv` directly into `~/.local/bin`:

```bash
curl -fsSL https://raw.githubusercontent.com/mouda/denv/main/install.sh | bash
```

### Method 2: Local Installer Script (`install.sh`)

If you have cloned the repository locally:

```bash
# Standard copy to ~/.local/bin
./install.sh

# Or developer symlink mode (updates automatically with git pull)
./install.sh --symlink

# Custom installation path
./install.sh --bin-dir /usr/local/bin
```

### Method 3: Standard UNIX Makefile

```bash
# Standard installation to ~/.local/bin (including shell completions)
make install

# Developer symlink mode
make link

# Clean uninstallation
make uninstall

# Run syntax verification and integration test suite
make test
```

> [!NOTE]
> Installation automatically registers shell completions for **Bash**, **Zsh**, and **Fish** in your user directory.

---

## Commands & Usage

```bash
denv [COMMAND] [OPTIONS] [--] [TARGET_DIR]
```

### Commands

| Command | Description |
| :--- | :--- |
| `init` | Bootstrap workspace configuration into `.envrc` (default). |
| `status` | Display current workspace environment status and direnv management state. |
| `clean` | Safely remove managed denv block from `.envrc` and revoke direnv authorization. |

### Options for `init` (default)

| Flag | Long Option | Description |
| :--- | :--- | :--- |
| `-b <NAME>` | `--backend <NAME>` | Explicitly select environment backend: `auto`, `uv`, `poetry`, `pipenv`, `pdm`, `hatch`, `conda`, `pixi`, `venv` (default: `auto`). |
| `-f` | `--force` | Replace or update managed `denv` block in `.envrc` in-place. |
| `-n` | `--no-create` | Do not create the virtual environment if missing. |
| `-g` | `--git-exclude` | Register `.envrc` and local virtual environment paths in `.git/info/exclude`. |
| | `--no-color` | Disable ANSI color sequences in output. |
| `-h` | `--help` | Print comprehensive help message and exit. |
| `-v` | `--version` | Display version information and exit. |

### Options for `status`

| Flag | Long Option | Description |
| :--- | :--- | :--- |
| `-q` | `--quiet` | Suppress output; exit `0` if workspace is configured, `1` otherwise (ideal for scripting/CI). |
| | `--no-color` | Disable ANSI color sequences in output. |
| `-h` | `--help` | Print help message and exit. |
| `-v` | `--version` | Display version information and exit. |

### Options for `clean`

| Flag | Long Option | Description |
| :--- | :--- | :--- |
| | `--no-color` | Disable ANSI color sequences in output. |
| `-h` | `--help` | Print help message and exit. |
| `-v` | `--version` | Display version information and exit. |

### Arguments

| Argument | Description |
| :--- | :--- |
| `TARGET_DIR` | Target workspace directory path. Defaults to current directory (`.`). |

---

## Environment Variables

| Variable | Description | Default |
| :--- | :--- | :--- |
| `DENV_ALLOW_ROOT` | Set to `1` to bypass the security block when running as superuser (UID `0`). | `0` |
| `DENV_DEBUG` | Set to `1` to enable verbose diagnostic traces on unexpected errors. | `0` |
| `NO_COLOR` | Disables colored output across terminal sessions when non-empty ([no-color.org](https://no-color.org/)). | `""` |

---

## Exit Codes

`denv` strictly adheres to standard POSIX and `<sysexits.h>` conventions:

| Exit Code | Constant | Meaning |
| :---: | :--- | :--- |
| **0** | `EX_OK` | Success. Workspace initialized and authorized with `direnv allow`. |
| **1** | `EX_ERR` | General runtime error (e.g., active workspace lock collision). |
| **2** | `EX_USAGE` | Invalid CLI invocation (unknown option or missing argument). |
| **77** | `EX_NO_PERM` | Permission denied (non-writable directory, root execution blocked, symlinked target). |
| **127** | `EX_CMD_NOT_FOUND` | Required binary (`direnv` or selected backend) is not installed in `$PATH`. |

---

## Backend Auto-Detection Rules

When `-b auto` (default) is active, `denv` inspects the project directory using the following precedence:

1. **Existing local virtual environments:** `.venv/bin/activate` or `venv/bin/activate`.
2. **Lockfiles:**
   - `uv.lock` &rarr; `uv`
   - `poetry.lock` &rarr; `poetry`
   - `Pipfile` / `Pipfile.lock` &rarr; `pipenv`
   - `pdm.lock` &rarr; `pdm`
   - `pixi.toml` / `pixi.lock` &rarr; `pixi`
   - `hatch.toml` &rarr; `hatch`
   - `environment.yml` / `environment.yaml` / `.conda` &rarr; `conda` (or `micromamba`/`mamba`)
3. **Project metadata (`pyproject.toml`):**
   - Contains `[tool.poetry]` &rarr; `poetry`
   - Contains `[tool.pdm]` &rarr; `pdm`
   - Contains `[tool.hatch]` &rarr; `hatch`
4. **Fallback:** If `uv` is installed, defaults to `uv`; otherwise defaults to standard `venv` via `python3 -m venv`.

---

## Architecture & Internals

### Managed Sentinel Blocks
`denv` encloses its activation logic inside standard sentinel comments:

```bash
# >>> denv initialize >>>
# Managed by denv v1.3.0
watch_file .env
dotenv_if_exists .env
if [[ -f .venv/bin/activate ]]; then
  source .venv/bin/activate
elif [[ -f /path/to/project/.venv/bin/activate ]]; then
  source /path/to/project/.venv/bin/activate
fi
# <<< denv initialize <<<
```

- When run on an existing `.envrc`, `denv` non-destructively preserves all custom environment variables, secrets, and layouts outside the markers.
- Re-running with `--force` updates **only** the content between the sentinels.

### Mutex Concurrency Protection
To prevent race conditions and partial file corruption in automated environments (such as CI or IDE background processes):
- `denv` creates an atomic directory lock (`.denv.lock`) containing its PID.
- Incomplete runs clean up their lock via `trap`.
- If an interrupted process left a stale lock behind, `denv` verifies whether the recorded PID is alive (`kill -0`) and purges stale locks automatically.

---

## License

This project is licensed under the [MIT License](LICENSE).
