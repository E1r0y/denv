#!/usr/bin/env python3
"""Build reproducible release assets and a Homebrew formula with a real checksum."""

import argparse
import gzip
import hashlib
import io
import os
from pathlib import Path
import re
import subprocess
import tarfile

from checksums import ROOT, FILES, manifest


def version():
    value = re.search(r'^readonly VERSION="([^"]+)"$', (ROOT / "bin/denv").read_text(), re.MULTILINE).group(1)
    installer = re.search(r'^readonly INSTALLER_VERSION="([^"]+)"$', (ROOT / "install.sh").read_text(), re.MULTILINE).group(1)
    if installer != value:
        raise ValueError("CLI and installer versions differ")
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", value):
        raise ValueError("Version must use semantic versioning")
    return value


def build(destination, tag=None):
    release_version = version()
    if tag is not None and tag != "v" + release_version:
        raise ValueError(f"Tag {tag!r} does not match v{release_version}")
    if f"## [{release_version}]" not in (ROOT / "CHANGELOG.md").read_text():
        raise ValueError("Changelog is missing the release version")
    if (ROOT / "checksums.sha256").read_text() != manifest():
        raise ValueError("checksums.sha256 is outdated")
    destination.mkdir(parents=True, exist_ok=True)
    prefix = f"denv-{release_version}"
    commit_time = subprocess.run(["git", "log", "-1", "--format=%ct"], cwd=ROOT, text=True, capture_output=True)
    epoch = int(os.environ.get("SOURCE_DATE_EPOCH", commit_time.stdout.strip() if commit_time.returncode == 0 else "0"))
    if not 0 <= epoch <= 0xFFFFFFFF:
        raise ValueError("SOURCE_DATE_EPOCH is outside the gzip timestamp range")
    files = set((*FILES, "install.sh", "Makefile", "checksums.sha256", "README.md", "CONTRIBUTING.md", "CHANGELOG.md", "LICENSE"))
    for directory in ("scripts", "tests", "packaging"):
        files.update(str(path.relative_to(ROOT)) for path in (ROOT / directory).rglob("*")
                     if path.is_file() and path.suffix in {".py", ".sh", ".txt", ".rb"})
    files = sorted(files)
    archive = destination / f"{prefix}.tar.gz"
    with archive.open("wb") as output:
        with gzip.GzipFile(filename="", mode="wb", fileobj=output, mtime=epoch) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as tar:
                for name in files:
                    content = (ROOT / name).read_bytes()
                    info = tarfile.TarInfo(f"{prefix}/{name}")
                    info.size = len(content)
                    info.mode = 0o755 if (ROOT / name).stat().st_mode & 0o111 else 0o644
                    info.mtime = epoch
                    tar.addfile(info, io.BytesIO(content))
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    formula = (ROOT / "packaging/homebrew/denv.rb").read_text()
    url = f"https://github.com/E1r0y/denv/releases/download/v{release_version}/{archive.name}"
    formula = re.sub(r'^  url ".*"$', f'  url "{url}"', formula, flags=re.MULTILINE)
    formula = re.sub(r'^  sha256 ".*"$', f'  sha256 "{digest}"', formula, flags=re.MULTILINE)
    formula = formula.replace("# Stable formula for the published release; --HEAD tracks main.", "# Generated release formula; --HEAD tracks main.")
    (destination / "denv.rb").write_text(formula)
    sums = [f"{digest}  {archive.name}\n"]
    sums.append(f"{hashlib.sha256((destination / 'denv.rb').read_bytes()).hexdigest()}  denv.rb\n")
    (destination / "SHA256SUMS").write_text("".join(sums))
    return archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--tag", help="verify the Git tag against the source version")
    args = parser.parse_args()
    try:
        print(build(args.destination, args.tag))
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
