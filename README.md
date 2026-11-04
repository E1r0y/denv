# denv

[![CI](https://github.com/E1r0y/denv/actions/workflows/ci.yml/badge.svg)](https://github.com/E1r0y/denv/actions/workflows/ci.yml)

Configure Python project environments and `.env` files for [direnv](https://direnv.net/).
Supports uv, Poetry, Pipenv, PDM, Hatch, Conda/Mamba/Micromamba, Pixi, and standard venv on Linux, macOS, and WSL.

## Quick start

Install **Bash >= 3.2**, **direnv >= 2.26**, and your chosen environment manager (or Python 3 for venv).
Workspace paths containing quotes, dollar signs, backticks, backslashes, or line breaks require **direnv >= 2.38**, whose loader handles those paths safely.
Enable the direnv hook in your interactive shell:

```bash
# Bash: ~/.bashrc
eval "$(direnv hook bash)"
# Zsh: ~/.zshrc or $ZDOTDIR/.zshrc
eval "$(direnv hook zsh)"
# Fish: ~/.config/fish/config.fish, or $XDG_CONFIG_HOME/fish/config.fish
direnv hook fish | source
```

Then run:

```bash
cd ~/projects/my-app
denv                    # Create/reuse an environment and configure .envrc
denv status             # Inspect configuration, environment, and authorization
denv clean              # Remove the managed block; keep custom settings and environments
```

`denv init` authorizes the entire `.envrc`, including existing custom content. To review it first:

```bash
denv init --no-allow
cat .envrc
direnv allow
```

## Installation

From a local checkout:

```bash
./install.sh                       # ~/.local/bin; /usr/local/bin when root
./install.sh --symlink             # Development installation
./install.sh --force               # Replace an existing installation
./install.sh --prefix "$HOME/apps/denv"
./install.sh --uninstall           # Remove the selected installation
```

The remote installer resolves `main` to one commit, downloads all components from that commit, and verifies their SHA256 hashes before replacing the executable:

```bash
curl -fsSL https://raw.githubusercontent.com/E1r0y/denv/main/install.sh | bash
# Pin a specific published commit or release that includes checksums.sha256:
curl -fsSL https://raw.githubusercontent.com/E1r0y/denv/main/install.sh | bash -s -- --ref COMMIT_SHA
# Update an existing installation:
curl -fsSL https://raw.githubusercontent.com/E1r0y/denv/main/install.sh | bash -s -- --force
```

`DENV_REF` supplies the remote ref; `DENV_REPO` overrides `E1r0y/denv` for forks. Checksums detect inconsistent or corrupted downloads; they are served by the same repository and are not release signatures. A failed download or checksum leaves the old executable intact.

With Make:

```bash
make install                         # Default prefix: ~/.local
make link                            # Symlink the executable and completions
make uninstall
make install PREFIX="/path with spaces" DESTDIR=/tmp/staging
```

`PREFIX`, `BINDIR`, `DATADIR`, `BASH_COMP_DIR`, `ZSH_COMP_DIR`, and `FISH_COMP_DIR` can be overridden. Use the same paths when uninstalling. The script and Makefile use different default Fish completion locations; uninstall with the method used for installation.

The installer copies Bash, Zsh, and Fish completion files. User paths respect `XDG_DATA_HOME` and `XDG_CONFIG_HOME`. For Zsh, add the completion directory to `fpath` **before** `compinit`:

```zsh
fpath=("${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions" $fpath)
autoload -Uz compinit
compinit
```

The installer prints the exact directory for custom prefixes. Bash may require `source /path/to/completions/denv` if bash-completion is not enabled; Fish custom prefixes may require adding the directory to `fish_complete_path`.

Homebrew: [packaging/homebrew/denv.rb](packaging/homebrew/denv.rb) contains the checksum for the last published stable release and supports `--HEAD`. Place it in your tap's `Formula/` directory. New releases include an updated `denv.rb` asset; no public tap is assumed to exist.

## Commands

```text
denv [init] [OPTIONS] [--] [TARGET_DIR]
denv status [-q|--quiet] [--] [TARGET_DIR]
denv clean [--] [TARGET_DIR]
```

`TARGET_DIR` defaults to `.`. All commands accept `--no-color`, `--help`, and `--version`. Use `--` before a target whose name starts with a dash or matches a command name.

| Init option | Behavior |
| --- | --- |
| `-b`, `--backend NAME` | `auto`, `uv`, `poetry`, `pipenv`, `pdm`, `hatch`, `conda`, `pixi`, or `venv` |
| `-f`, `--force` | Regenerate a valid managed block while preserving custom content |
| `-n`, `--no-create` | Reuse an existing environment; never create one |
| `-g`, `--git-exclude` | Add local artifacts and `.env` files to `.git/info/exclude`, keeping `.env.example` visible |
| `--no-allow` | Leave direnv authorization unchanged instead of running `direnv allow` |

For `uv` and `venv`, `--no-create` can write a **pending** configuration pointing to a missing `.venv`. It fails clearly on activation and `status -q` returns 1 until the environment exists. Other managers require an existing usable environment with `--no-create`; no dynamic layout is used as a fallback.

Repeated `init` without `--force` leaves the managed block unchanged and skips environment manager calls. Use `--force` after creating or replacing an environment, changing managers, or moving a project.

`status -q` returns 0 only when the managed block is valid, its environment exists, and the `.envrc` is authorized. It does not execute arbitrary `.envrc` code to prove that custom commands succeed. Old blocks without environment metadata require `denv init --force` to report readiness.

`clean` acquires the same lock as `init`, revokes authorization while `.envrc` still exists, and removes only the managed block. It leaves custom content, virtual environments, and Git exclusions in place.

Workspace paths are resolved to physical directories. When invoking `direnv exec` directly, pass a physical path: some direnv versions canonicalize paths for `allow` but keep directory aliases for `exec`. On macOS, `/var` and `/tmp` are commonly aliases of `/private/var` and `/private/tmp`.

## Backend behavior

Auto-detection prefers existing `.venv/bin/activate` or `venv/bin/activate`, then the following project files in order:

| Files | Backend |
| --- | --- |
| `uv.lock` | uv |
| `poetry.lock` | Poetry |
| `Pipfile` or `Pipfile.lock` | Pipenv |
| `pdm.lock` | PDM |
| `pixi.toml`, `pixi.lock`, or `[tool.pixi]` | Pixi |
| `hatch.toml` | Hatch |
| `environment.yml`, `environment.yaml`, or `.conda/` | Conda |
| `[tool.poetry]`, `[tool.pdm]`, or `[tool.hatch]` in `pyproject.toml` | Matching manager |
| Otherwise | uv if installed, else Python venv |

- **uv/venv:** use local `.venv`. Venv enforces numeric `.python-version` values against the actual interpreter version; it fails instead of silently switching versions. uv also supports its own named interpreter selectors.
- **Poetry/Pipenv/PDM/Hatch:** resolve and validate the manager's environment, creating it when allowed. PDM reads a saved `.pdm-python` or queries the in-project environment without creating one. These tools may initialize an environment without installing all project dependencies; run the manager's normal dependency installation command when needed.
- **Conda/Mamba/Micromamba:** use local `.conda`, overriding an environment file's global name to avoid collisions between projects. Creation requires `environment.yml` or `environment.yaml`. Micromamba takes precedence, then Mamba, then Conda. Activation still invokes the selected manager's shell hook.
- **Pixi:** initialize the default environment, then store its activation hook in `.envrc`. Entering the directory does not run Pixi, install packages, or modify the lockfile. Regenerate with `--force` after changing dependencies or activation settings.

Python virtual environments and captured absolute paths are not generally relocatable. Recreate environments as required by the manager after moving a project.

## File safety and locks

A managed block has one exact opening marker and one exact closing marker:

```bash
# >>> denv initialize >>>
# Managed by denv v1.4.0
# ... generated environment metadata and activation ...
# <<< denv initialize <<<
```

Missing, nested, and duplicate markers cause a failure before changing `.envrc` or invoking a backend. CRLF markers are accepted. Writes use temporary files and atomic rename, retaining an existing file's permissions. Symlinked and non-regular `.envrc` targets are refused.

`init` and `clean` share `.denv.lock/`. A live PID or a lock without a valid PID blocks concurrent changes. Dead-PID recovery is serialized using `.denv.lock.recovery/`. After a hard kill, a PID-less lock or recovery guard may require manual removal **after verifying no denv process is active**. Locks assume a local filesystem and cooperative processes; they are not distributed locks.

Root writes are refused unless `DENV_ALLOW_ROOT=1`. `DENV_DEBUG=1` enables unexpected-error locations. `NO_COLOR`, `TERM=dumb`, and `--no-color` disable colors. Command diagnostics go to stderr; status, help, and version data go to stdout.

| Exit | Meaning |
| --- | --- |
| 0 | Successful operation; for status, workspace is ready |
| 1 | General error, lock conflict, invalid block, or workspace not ready |
| 2 | Invalid arguments |
| 77 | Permissions, unsafe target, or root write refused |
| 127 | Required command is missing |

Failures from external manager commands may retain that command's nonzero exit code. These are CLI conventions, not a complete implementation of `sysexits.h`.

## Development and performance

See [CONTRIBUTING.md](CONTRIBUTING.md). Run `make test` for syntax, lint, filesystem/installer/backend tests, and available shell completion engines. Update distributed-file checksums with `make checksums`.

`make bench` measures complete `direnv exec` runs against empty and venv workspaces, reporting median and p95 times with the system and direnv version. It includes process startup and is not an interactive-shell latency guarantee. Conda hooks and custom `.envrc` commands have different costs; no fixed timing is promised.

MIT licensed; see [LICENSE](LICENSE).
