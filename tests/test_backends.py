#!/usr/bin/env python3
"""Backend contracts and optional smoke tests against installed managers."""

import json
import os
import shutil
import unittest

from support import BASH, REPO, WorkspaceTest


class BackendTests(WorkspaceTest):
    def adapter(self, name, environment=None):
        (self.tools / name).symlink_to(REPO / "tests/fixtures/backend.py")
        # A shebang interpreter must be executable in source archives as well.
        self.env["DENV_TEST_ENV"] = str(environment or self.root / "external environment")
        self.env["DENV_TEST_CALLS"] = str(self.root / "calls.jsonl")

    def calls(self):
        path = self.root / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_create_resolve_and_activate_all_backends(self):
        for name in ("uv", "poetry", "pipenv", "pdm", "hatch", "conda", "mamba", "micromamba", "pixi"):
            with self.subTest(backend=name):
                self.adapter(name)
                project = self.work / name
                project.mkdir()
                (project / ".env").write_text("DENV_FIXTURE_VALUE=loaded\n")
                (project / "environment.yml").write_text("name: ignored-in-favor-of-local-prefix\n")
                backend = "conda" if name in {"mamba", "micromamba"} else name
                self.denv("-b", backend, project)
                self.run_command(BASH, "-n", project / ".envrc")
                self.denv("status", "-q", project)
                before = len(self.calls())
                code = "import os; assert os.environ['DENV_FIXTURE_VALUE']=='loaded'; assert os.environ.get('VIRTUAL_ENV') or os.environ.get('CONDA_PREFIX')"
                self.run_command("direnv", "exec", project, "python3", "-c", code)
                if name != "conda" and name not in {"mamba", "micromamba"}:
                    self.assertEqual(len(self.calls()), before, "directory entry must not launch the manager")
                (self.tools / name).unlink()
                shutil.rmtree(self.root / "external environment", ignore_errors=True)

    def test_no_create_checks_existing_environment_without_initializing(self):
        for name in ("poetry", "pipenv", "pdm", "hatch", "conda", "pixi"):
            with self.subTest(backend=name):
                self.adapter(name)
                project = self.work / name
                project.mkdir()
                self.denv("-b", name, "-n", project, expected=1)
                self.assertFalse((project / ".envrc").exists())
                self.assertFalse((self.root / "external environment").exists())
                self.assertFalse((project / ".conda").exists())
                self.assertFalse((project / ".pixi").exists())
                (self.tools / name).unlink()
        self.assertFalse(any("create" in call or "install" in call for call in self.calls()))

    def test_failed_local_creation_removes_only_new_environment(self):
        self.adapter("uv")
        self.env["DENV_TEST_FAIL_CREATE"] = "1"
        self.denv("-b", "uv", expected=42)
        self.assertFalse((self.work / ".venv").exists())
        self.assertFalse((self.work / ".envrc").exists())
        existing = self.work / ".venv"
        existing.mkdir()
        (existing / "keep").write_text("existing data")
        self.denv("-b", "uv", expected=42)
        self.assertEqual((existing / "keep").read_text(), "existing data")

    def test_no_allow_requires_explicit_authorization(self):
        self.adapter("uv")
        self.denv("-b", "uv", "--no-allow")
        self.denv("status", "-q", expected=1)
        self.run_command("direnv", "allow", self.work)
        self.denv("status", "-q")

    def test_metadata_cannot_execute_shell_code(self):
        self.adapter("uv")
        self.denv("-b", "uv")
        envrc = self.work / ".envrc"
        contents = envrc.read_text()
        contents = "\n".join(
            "# denv environment: $(touch BAD)" if line.startswith("# denv environment:") else line
            for line in contents.splitlines()
        ) + "\n"
        envrc.write_text(contents)
        self.denv("status", expected=1)
        self.assertFalse((self.work / "BAD").exists())

    def test_real_venv_activation(self):
        (self.work / ".env").write_text("DENV_REAL_ENV=works\n")
        self.denv("-b", "venv", timeout=60)
        self.run_command("direnv", "exec", self.work, "python3", "-c", "import os; assert os.getenv('DENV_REAL_ENV')=='works'; assert os.getenv('VIRTUAL_ENV')")

    @unittest.skipUnless(os.environ.get("DENV_TEST_REAL_BACKENDS"), "set DENV_TEST_REAL_BACKENDS to smoke-test installed managers")
    def test_real_managers(self):
        for name in os.environ["DENV_TEST_REAL_BACKENDS"].split(","):
            with self.subTest(backend=name):
                self.assertIsNotNone(shutil.which(name), f"{name} is required by DENV_TEST_REAL_BACKENDS")
                project = self.work / name
                project.mkdir()
                (project / "pyproject.toml").write_text(
                    '[project]\nname="denv-fixture"\nversion="0.0.0"\nrequires-python=">=3.9"\n'
                    '[tool.poetry]\npackage-mode=false\n'
                    '[tool.hatch.envs.default]\nskip-install=true\n'
                )
                (project / "Pipfile").write_text("[packages]\n")
                self.denv("-b", name, "-n", project, expected=0 if name == "uv" else 1, timeout=60)
                self.assertFalse((project / ".venv").exists())
                self.denv("-b", name, "-f", project, timeout=60)
                self.denv("status", "-q", project)
                self.run_command("direnv", "exec", project, "python3", "-c", "import os; assert os.getenv('VIRTUAL_ENV')")

    @unittest.skipUnless(os.environ.get("DENV_TEST_REAL_CONDA_PIXI"), "set DENV_TEST_REAL_CONDA_PIXI for isolated Conda/Pixi smoke tests")
    def test_real_conda_and_pixi(self):
        for name in os.environ["DENV_TEST_REAL_CONDA_PIXI"].split(","):
            with self.subTest(backend=name):
                self.assertIsNotNone(shutil.which(name))
                project = self.work / name
                project.mkdir()
                environment = {"MAMBA_ROOT_PREFIX": str(self.root / "mamba-root"), "PIXI_CACHE_DIR": str(self.root / "pixi-cache")}
                if name == "pixi":
                    import platform
                    target = "osx-arm64" if platform.system() == "Darwin" and platform.machine() == "arm64" else "osx-64" if platform.system() == "Darwin" else "linux-64"
                    (project / "pixi.toml").write_text(f'[workspace]\nname="denv-fixture"\nchannels=[]\nplatforms=["{target}"]\n[dependencies]\n')
                    backend = "pixi"
                else:
                    (project / "environment.yml").write_text("name: denv-fixture\ndependencies: []\n")
                    backend = "conda"
                self.denv("-b", backend, "-n", project, expected=1, env=environment)
                self.denv("-b", backend, project, env=environment)
                self.denv("status", "-q", project, env=environment)
                self.run_command("direnv", "exec", project, "python3", "-c", "import os; assert os.getenv('CONDA_PREFIX')", env=environment)


if __name__ == "__main__":
    unittest.main(verbosity=2)
