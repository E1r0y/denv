"""Isolated command fixtures shared by the integration tests."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
DENV = REPO / "bin" / "denv"
BASH = os.environ.get("DENV_TEST_BASH", "bash")


class WorkspaceTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="denv-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.work = self.root / "workspace with spaces"
        self.work.mkdir()
        self.tools = self.root / "tools"
        self.tools.mkdir()
        user_home = self.root / "home"
        user_home.mkdir()
        self.env = dict(os.environ)
        for key in list(self.env):
            if key.startswith("DIRENV_") or key in {"VIRTUAL_ENV", "CONDA_PREFIX", "DENV_REF", "DENV_REPO", "ZDOTDIR"}:
                self.env.pop(key)
        self.env.update(
            HOME=str(user_home),
            XDG_CONFIG_HOME=str(user_home / "config"),
            XDG_CACHE_HOME=str(user_home / "cache"),
            XDG_DATA_HOME=str(user_home / "data"),
            DIRENV_CONFIG=str(user_home / "config" / "direnv"),
            UV_CACHE_DIR=str(user_home / "cache" / "uv"),
            UV_PYTHON_DOWNLOADS="never",
            GIT_CONFIG_GLOBAL=os.devnull,
            DENV_ALLOW_ROOT="1",
            NO_COLOR="1",
            SHELL="/bin/bash",
            TERM="dumb",
            VIRTUALENV_NO_PERIODIC_UPDATE="1",
            PIP_DISABLE_PIP_VERSION_CHECK="1",
            PATH=str(self.tools) + os.pathsep + self.env["PATH"],
        )

    def run_command(self, *args, expected=0, cwd=None, env=None, timeout=60):
        result = subprocess.run(
            [str(arg) for arg in args],
            cwd=cwd or self.work,
            env=self.env | (env or {}),
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        if expected is not None:
            self.assertEqual(
                result.returncode,
                expected,
                f"Command {args!r}:\n{result.stdout}\n{result.stderr}",
            )
        return result

    def denv(self, *args, **kwargs):
        return self.run_command(BASH, DENV, *args, **kwargs)

    def stub(self, name, source):
        path = self.tools / name
        path.write_text(source)
        path.chmod(0o755)
        return path
