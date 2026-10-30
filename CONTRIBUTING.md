# Contributing to denv

Thank you for your interest in contributing to `denv`! This document outlines guidelines and instructions for submitting contributions, reporting issues, and testing changes locally.

---

## Code of Conduct

We are committed to providing a welcoming, inclusive, and harassment-free environment for everyone. Please be respectful and constructive in all discussions, pull requests, and issue reports.

---

## Getting Started & Repository Structure

`denv` is intentionally built with zero heavy runtime dependencies (pure Bash and standard UNIX utilities).

```
denv/
├── bin/
│   └── denv                     # Main CLI executable
├── completions/
│   ├── bash/denv                # Bash tab completions
│   ├── zsh/_denv                # Zsh tab completions
│   └── fish/denv.fish           # Fish tab completions
├── tests/
│   └── test_denv.sh             # Integration test suite
├── install.sh                   # Production-ready installer (local & remote)
├── Makefile                     # UNIX install, link, test targets
└── .github/
    └── workflows/ci.yml         # CI pipeline (Ubuntu & macOS)
```

---

## Local Development Workflow

### 1. Prerequisites

- **Bash** `>= 3.2`
- **direnv** `>= 2.21`
- **shellcheck** (optional, recommended for static analysis)
- `make` and standard POSIX utilities (`awk`, `sed`, `grep`, `mktemp`)

### 2. Fast Developer Symlink Mode

To work on `denv` and have your edits immediately reflected in your terminal:

```bash
make link
```

This symlinks `bin/denv` and shell completions directly into `~/.local/bin` and `~/.local/share/...`.

To remove the symlinks:

```bash
make uninstall
```

### 3. Running the Test Suite

Always verify your changes before opening a pull request:

```bash
make test
```

`make test` performs:
1. Syntax validation (`bash -n`) across all scripts.
2. Static analysis (`shellcheck`) on `bin/denv`, `install.sh`, `tests/test_denv.sh`, and `completions/bash/denv` (if `shellcheck` is installed).
3. The end-to-end integration test suite (`tests/test_denv.sh`).

---

## Code Conventions & Design Principles

When modifying or adding features to `denv`, strictly adhere to these architectural rules:

1. **Strict Shell Safety:**
   - Always run under `set -Eeuo pipefail`.
   - Never quote flags dynamically; quote all variables and array expansions (`"$var"`, `"${array[@]}"`).
2. **Ahead-of-Time (AoT) Performance:**
   - Never write dynamic logic into `.envrc` that executes slow subshells or launches Python during directory transitions.
   - All path resolutions must happen once at bootstrap time in `denv`, writing static `source /path/to/bin/activate` or `eval` blocks.
3. **Atomic & Non-Destructive File Operations:**
   - Always write to a temporary file via `mktemp` and atomically rename (`mv -f`).
   - Do not overwrite custom user variables in `.envrc`. All denv-managed logic must remain strictly inside the sentinel markers:
     ```bash
     # >>> denv initialize >>>
     ...
     # <<< denv initialize <<<
     ```
4. **Stream Separation:**
   - Informational logs, warnings, and errors must flow to `stderr` (`>&2`).
   - `stdout` is reserved exclusively for CLI data (`denv status`), `--help`, and `--version`.
5. **Standard Exit Codes:**
   - Use sysexits-style exit codes: `0` (EX_OK), `1` (EX_ERR), `2` (EX_USAGE), `77` (EX_NO_PERM), `127` (EX_CMD_NOT_FOUND).
6. **Path Escaping:**
   - Always escape paths written to shell scripts using `printf '%q'`.

---

## Adding a New Environment Backend

To add support for a new Python package or environment manager:

1. **Detect backend** in `detect_backend()` and `detect_backend_source()` (`bin/denv`):
   - Check for characteristic lockfiles or configuration files (e.g. `foo.lock`, `foo.toml`).
2. **Resolve activation path** in `build_activation_snippet()`:
   - Query the tool for its virtual environment path.
   - Fall back to dynamic layout if the environment is uninitialized and `--no-create` is passed.
3. **Update valid backends list:**
   - Add the backend name to `VALID_BACKENDS` in `bin/denv`.
   - Update completions in `completions/bash/denv`, `completions/zsh/_denv`, and `completions/fish/denv.fish`.
4. **Add integration test:**
   - Add a test case in `tests/test_denv.sh` verifying that the tool's lockfile triggers backend detection.
5. **Update documentation:**
   - Add the backend to `README.md`.

---

## Submitting Pull Requests

1. Fork the repository and create your branch from `main`:
   ```bash
   git checkout -b feature/my-new-feature
   ```
2. Commit your changes with clear, descriptive commit messages (e.g. `feat: add support for foo backend` or `fix: handle edge case in path escaping`).
3. Ensure all tests pass (`make test`).
4. Push your branch to GitHub and open a Pull Request.
