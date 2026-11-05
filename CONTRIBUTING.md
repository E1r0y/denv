# Contributing

The installed CLI is a single Bash script. Keep runtime compatibility with Bash 3.2, GNU/BSD utilities, and direnv 2.26 or later.

## Branches and pull requests

Start each task in a short-lived branch and keep each PR focused on one change. Push commits to that branch, open a PR against `main`, and review its diff and test results before merging.

`main` requires a PR, an up-to-date base, and successful Ubuntu, macOS, Python-manager, and Micromamba/Pixi checks from GitHub Actions. Direct updates, force pushes, and deletion are blocked, including for administrators. All review conversations must be resolved. Required approving reviews are set to zero so a sole maintainer can complete their own work.

Use squash merge. GitHub deletes merged branches automatically and supports auto-merge after requirements pass. Dependency updates follow the same process; update an outdated PR branch and rerun checks before merging. If the API token lacks workflow scope, update workflow branches using normal Git authentication rather than bypassing protection.

## Development

Use `./install.sh --symlink` or `make link` for local development; use `--force` when replacing an existing script installation. Tests write to temporary homes, caches, and workspaces. They must not change your normal direnv authorization or project environments.

Development checks require Python 3.12+, Bash, direnv, and make. ShellCheck, Zsh, and Fish enable additional checks; CI requires all three.

```bash
make checksums       # After changing bin/denv or completion files
make test
# Optional smoke tests against actual installed managers:
DENV_TEST_REAL_BACKENDS=uv,poetry,pipenv,pdm,hatch make test
# Optional Conda/Pixi smoke tests (isolated, dependency-free environments):
DENV_TEST_REAL_CONDA_PIXI=micromamba,pixi python3 tests/test_backends.py BackendTests.test_real_conda_and_pixi
# Reproducible performance measurements:
make bench
```

`tests/requirements-managers.txt` pins the manager versions exercised by CI. Install those into a disposable development environment when running smoke tests. They are not runtime dependencies of denv.

To test an older Bash, put a `bash` symlink to that binary first in PATH and pass `BASH=/path/to/bash` to make. This covers scripts whose shebang uses `/usr/bin/env bash` as well as direct test invocations.

## Structure

- `bin/denv`: common argument parsing; environment detection and resolution; safe file operations; lock handling; init/status/clean.
- `install.sh`: atomic local/remote installation, immutable commit resolution, checksum verification, and shell setup hints.
- `completions/`: Bash, Zsh, and Fish completion definitions.
- `tests/test_denv.sh`: basic CLI coverage with a strict background-process runner.
- `tests/test_regressions.sh`: regressions for the audited failure modes.
- `tests/test_*.py`: filesystem/concurrency, real completion engines, backend command contracts, installer transports, and release artifacts.
- `tests/fixtures/backend.py`: offline command adapters; unexpected manager commands fail.
- `scripts/checksums.py`: distributed-file manifest.
- `scripts/build_release.py`: deterministic tarball, SHA256SUMS, and generated Homebrew formula.
- `scripts/verify_release.py`: require the release commit to belong to `main` and have successful push CI.
- `scripts/benchmark.py`: complete direnv exec measurements.

## Changes and tests

Exercise behavior through the CLI and command adapters, including the generated `.envrc` loading through real direnv. Reproduce a bug before fixing it, and retain a regression that catches its actual symptom. Run tests outside conditionals that disable Bash errexit; an early failed assertion must fail its test.

Keep backend detection and argument parsing centralized. A new backend needs read-only lookup, validated environment paths, explicit creation, defined `--no-create` behavior, command-contract tests, and completion/documentation updates. Directory entry must not silently create environments or install dependencies.

Preserve user content and permissions. Validate managed markers before any side effect; use the workspace lock for every mutating command. Write replacements completely before atomic rename. Never infer that a PID-less lock is stale. Do not evaluate configuration metadata as shell code. Quote shell paths with `printf '%q'`.

Diagnostics belong on stderr; help, version, and status data belong on stdout. Maintain the documented exit conventions and report external command failures honestly.

## Releases

1. Update `VERSION` in `bin/denv`, `INSTALLER_VERSION` in `install.sh`, and the changelog to the same new version.
2. Run `make checksums` and `make test`.
3. Preview assets outside the repository: `python3 scripts/build_release.py /tmp/denv-release --tag vX.Y.Z`.
4. Commit changes in a working branch, merge the PR after its checks pass, and wait for successful push CI on `main`.
5. Create and push the matching tag at that exact tested commit when ready to publish.

The release workflow verifies that the commit belongs to `main` and has successful push CI, checks the version/tag, runs tests, and publishes the tarball, SHA256SUMS, and an updated `denv.rb`. It marks prerelease tags appropriately. Copy that generated formula into your Homebrew tap. The checked-in formula remains usable for the last stable release; its `head` spec follows main. Archive timestamps use `SOURCE_DATE_EPOCH` when supplied, otherwise the checkout's commit time (zero outside a Git checkout).

Keep discussion constructive. Bug reports should include versions, a minimal reproduction, and redacted diagnostic output. Do not include real `.env` values, access tokens, or private keys.
