#!/usr/bin/env python3
"""Write or verify the download manifest; the installer verifies the same files."""

import argparse
import hashlib
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
FILES = (
    "bin/denv",
    "completions/bash/denv",
    "completions/zsh/_denv",
    "completions/fish/denv.fish",
)


def manifest():
    return "".join(f"{hashlib.sha256((ROOT / name).read_bytes()).hexdigest()}  {name}\n" for name in FILES)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="update checksums.sha256 after changing distributed files")
    args = parser.parse_args()
    target = ROOT / "checksums.sha256"
    expected = manifest()
    if args.write:
        target.write_text(expected)
    elif not target.exists() or target.read_text() != expected:
        print("Download checksums are outdated. Run: python3 scripts/checksums.py --write", file=sys.stderr)
        return 1
    print("Download checksums verified." if not args.write else "Updated checksums.sha256.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
