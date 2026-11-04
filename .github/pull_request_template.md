## Description

Please include a summary of the changes, motivation, and context behind this PR.

Fixes #(issue)

## Type of Change

- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Test suite enhancement

## Checklist

- [ ] My code follows the code conventions of this project (`set -Eeuo pipefail`, stream separation).
- [ ] I have verified that syntax checks pass (`bash -n`).
- [ ] I have run the integration test suite (`make test`) and all tests pass.
- [ ] I have updated `checksums.sha256` with `make checksums` if distributed files changed.
- [ ] I have updated documentation (`README.md`, `CONTRIBUTING.md`) if applicable.
- [ ] I have updated shell completions (`completions/`) if new flags or backends were introduced.
- [ ] Fixes include a regression that catches the original failure, including generated `.envrc` behavior where relevant.
