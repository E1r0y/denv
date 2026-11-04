#!/usr/bin/env python3
"""Verify the packaged files, reproducibility, formula, and tag guard."""

import hashlib
from pathlib import Path
import sys
import tarfile
import unittest

from support import BASH, REPO, WorkspaceTest


class ReleaseTests(WorkspaceTest):
    def build(self, destination, *extra, expected=0):
        return self.run_command(sys.executable, REPO / "scripts/build_release.py", destination, *extra, expected=expected)

    def test_reproducible_archive_formula_and_local_install(self):
        first, second = self.root / "first", self.root / "second"
        self.build(first)
        self.build(second)
        archive = next(first.glob("*.tar.gz"))
        version = self.denv("--version").stdout.strip().split()[-1]
        self.assertEqual(archive.read_bytes(), (second / archive.name).read_bytes())
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        formula = (first / "denv.rb").read_text()
        self.assertIn(f'sha256 "{digest}"', formula)
        self.assertIn(f"/releases/download/v{version}/denv-{version}.tar.gz", formula)
        self.assertIn(f"{digest}  {archive.name}", (first / "SHA256SUMS").read_text())
        extracted = self.root / "unpacked"
        extracted.mkdir()
        with tarfile.open(archive) as package:
            names = package.getnames()
            self.assertFalse(any(".." in Path(name).parts for name in names))
            self.assertTrue(all(name.startswith(f"denv-{version}/") for name in names))
            package.extractall(extracted, filter="data")
        prefix = self.root / "installed"
        self.run_command(BASH, extracted / f"denv-{version}/install.sh", "--prefix", prefix)
        self.run_command(BASH, prefix / "bin/denv", "--version")

    def test_wrong_release_tag_is_rejected(self):
        result = self.build(self.root / "wrong", "--tag", "v0.0.0", expected=2)
        self.assertIn("does not match", result.stderr)
        self.assertFalse((self.root / "wrong").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
