# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.4.0] - 2026-11-05

### Fixed
- Reject incomplete, nested, and duplicate managed blocks before changing files; accept CRLF markers and preserve file permissions.
- Serialize `init` and `clean`, protect locks that have not written a PID yet, and serialize stale-lock recovery.
- Preserve installed executables on download failures and verify all remote components from one immutable commit.
- Enforce requested Python versions, fix PDM environment lookup, and validate environment paths returned by managers.
- Honor `--no-create` without dynamic Poetry or Pipenv layouts creating environments later.
- Correct Bash paths with spaces, Zsh subcommand completion, Makefile quoting, and shell setup instructions.
- Fail the test suite on intermediate assertion errors and isolate test homes and caches.
- Require direnv 2.26 or later for `dotenv_if_exists`.

### Changed
- `status -q` succeeds only for a valid managed block, an existing environment, and current direnv authorization.
- Repeated initialization without `--force` skips manager queries and environment creation.
- Conda uses a project-local `.conda` prefix, creating it from the environment file when needed.
- Pixi activation is captured at initialization with installation and lockfile updates disabled during hook generation.
- Existing installations require `install.sh --force`; uninstall only removes the selected installation scope.

### Added
- `--no-allow` for reviewing generated configuration before authorizing it.
- Backend contract tests, real-manager smoke tests, concurrent-process tests, and interactive shell completion tests.
- Reproducible release archives, generated Homebrew formulas, verified download manifests, and a local benchmark.

## [1.3.0] - 2026-10-30

### Added
- Multi-backend auto-detection for Python project managers:
  - Astral `uv` (`uv.lock`, fallback)
  - `poetry` (`poetry.lock`, `[tool.poetry]`)
  - `pipenv` (`Pipfile`, `Pipfile.lock`)
  - `pdm` (`pdm.lock`, `[tool.pdm]`)
  - `hatch` (`hatch.toml`, `[tool.hatch]`)
  - `conda` / `mamba` / `micromamba` (`environment.yml`, `.conda`)
  - `pixi` (`pixi.toml`, `pixi.lock`)
  - Standard `venv` (`python3 -m venv`)
- Ahead-of-Time (AoT) Path Resolution architecture reducing directory-switch terminal latency to ~1–2 ms.
- Safe atomic `.envrc` updates using `mktemp` and in-place marker replacement without altering user-defined environment variables.
- Enterprise mutex locking mechanism via `.denv.lock` with live PID check (`kill -0`) and automatic recovery from stale locks.
- Defensive security: refusal to run as root (`UID 0`), rejection of symlinked `.envrc`, and sanitization of `.python-version`.
- Git hygiene option (`--git-exclude` / `-g`) to hide local `.envrc` and virtual environment files in `.git/info/exclude`.
- Status diagnosis subcommand (`denv status`) with terminal styling, color detection, and scripting-friendly `--quiet` mode.
- Clean removal subcommand (`denv clean`) with non-destructive marker cleanup and `direnv deny` revocation.
- Native shell completions for Bash, Zsh, and Fish.
- Universal installer script (`install.sh`) supporting local installation, developer symlinking, custom binary directories, and `curl | bash` pipelines.
- Continuous Integration workflow running syntax and integration tests across Ubuntu and macOS runners.
