# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

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
