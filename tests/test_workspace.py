#!/usr/bin/env python3
"""Filesystem, concurrency, argument parsing, and test-runner regressions."""

from pathlib import Path
import re
import shlex
import subprocess
import time
import unittest

from support import BASH, DENV, REPO, WorkspaceTest


class WorkspaceTests(WorkspaceTest):
    def test_status_consumes_complete_direnv_output(self):
        self.denv("-b", "venv", "-n")
        environment = self.work / ".venv/bin"
        environment.mkdir(parents=True)
        (environment / "activate").write_text("# fixture activation\n")
        self.stub("direnv", '''#!/usr/bin/env bash
[[ "$1" == status ]] || exit 99
printf 'Found RC allowed 0\\n'
sleep 0.1
printf 'Found RC allowPath /tmp/fixture\\n'
''')
        self.denv("status", "-q")

    def wait_for(self, path):
        deadline = time.monotonic() + 5
        while not path.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(path.exists(), "background command did not reach its synchronization point")

    def finish_process(self, process, release):
        release.touch()
        try:
            output, error = process.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate()
            self.fail("background command failed to finish")
        self.assertEqual(process.returncode, 0, output + error)

    def test_pid_write_window_cannot_be_reaped(self):
        ready = self.root / "ready"
        release = self.root / "release"
        mkdir = shutil_which("mkdir", self.env["PATH"])
        self.stub("mkdir", f'''#!/usr/bin/env bash
{shlex.quote(mkdir)} "$@" || exit
if [[ "$*" == *'.denv.lock' && "${{DENV_TEST_PAUSE:-}}" == 1 ]]; then
  touch {shlex.quote(str(ready))}
  while [[ ! -f {shlex.quote(str(release))} ]]; do sleep 0.01; done
fi
''')
        first = subprocess.Popen([BASH, DENV, "-b", "venv", "-n", self.work], cwd=self.work,
                                 env=self.env | {"DENV_TEST_PAUSE": "1"}, text=True,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            self.wait_for(ready)
            self.denv("-b", "venv", "-n", expected=1)
            self.denv("clean", expected=1)
            self.assertTrue((self.work / ".denv.lock").is_dir())
        finally:
            self.finish_process(first, release)

    def test_init_and_clean_cannot_overlap(self):
        ready = self.root / "ready"
        release = self.root / "release"
        self.stub("uv", f'''#!/usr/bin/env bash
touch {shlex.quote(str(ready))}
while [[ ! -f {shlex.quote(str(release))} ]]; do sleep 0.01; done
mkdir -p "${{@: -1}}/bin"
printf '# activation\\n' > "${{@: -1}}/bin/activate"
''')
        first = subprocess.Popen([BASH, DENV, "-b", "uv", self.work], cwd=self.work,
                                 env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            self.wait_for(ready)
            self.denv("-b", "venv", "-n", expected=1)
            self.denv("clean", expected=1)
            self.assertFalse((self.work / ".envrc").exists())
        finally:
            self.finish_process(first, release)

    def test_stale_lock_recovery_is_serialized(self):
        lock = self.work / ".denv.lock"
        lock.mkdir()
        (lock / "pid").write_text("99999999\n")
        ready, release = self.root / "ready", self.root / "release"
        rm = shutil_which("rm", self.env["PATH"])
        self.stub("rm", f'''#!/usr/bin/env bash
if [[ "$*" == *'.denv.lock/pid' ]]; then
  touch {shlex.quote(str(ready))}
  while [[ ! -f {shlex.quote(str(release))} ]]; do sleep 0.01; done
fi
exec {shlex.quote(rm)} "$@"
''')
        first = subprocess.Popen([BASH, DENV, "-b", "venv", "-n", self.work], cwd=self.work,
                                 env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            self.wait_for(ready)
            self.denv("-b", "venv", "-n", expected=1)
            self.denv("clean", expected=1)
            self.assertEqual((lock / "pid").read_text(), "99999999\n")
        finally:
            self.finish_process(first, release)
        self.assertFalse(lock.exists())
        self.assertFalse((self.work / ".denv.lock.recovery").exists())

    def test_failed_transform_does_not_replace_existing_file(self):
        self.denv("-b", "venv", "-n")
        original = (self.work / ".envrc").read_bytes()
        awk = shutil_which("awk", self.env["PATH"])
        self.stub("awk", f'''#!/usr/bin/env bash
if [[ "$*" == *'skip=1'* ]]; then exit 42; fi
exec {shlex.quote(awk)} "$@"
''')
        self.denv("-b", "venv", "-n", "-f", expected=1)
        self.assertEqual((self.work / ".envrc").read_bytes(), original)
        self.denv("clean", expected=1)
        self.assertEqual((self.work / ".envrc").read_bytes(), original)
        self.assertFalse(list(self.work.glob(".envrc.tmp.*")))

    def test_symlinks_and_directories_are_rejected(self):
        original = self.root / "original"
        original.write_text("keep")
        envrc = self.work / ".envrc"
        envrc.symlink_to(original)
        self.denv("-b", "venv", "-n", expected=77)
        self.denv("clean", expected=77)
        self.denv("status", "-q", expected=1)
        self.assertEqual(original.read_text(), "keep")
        envrc.unlink()
        envrc.mkdir()
        self.denv("-b", "venv", "-n", expected=77)
        self.assertEqual(list(envrc.iterdir()), [])

    def test_generated_activation_quotes_shell_metacharacters(self):
        project = self.work / "quotes ' and $(touch BAD)"
        environment = project / ".venv"
        (environment / "bin").mkdir(parents=True)
        (environment / "bin/activate").write_text("export DENV_QUOTED=yes\n")
        version = self.run_command("direnv", "version").stdout.strip().split(".")
        if tuple(int(value) for value in version[:2]) < (2, 38):
            self.denv("-n", project, expected=1)
            self.assertFalse((project / ".envrc").exists())
            return
        self.denv("-n", project)
        self.denv("-n", "-f", project)
        self.run_command("direnv", "exec", project, "sh", "-c", 'test "$DENV_QUOTED" = yes')
        self.assertFalse((project / "BAD").exists())

    def test_old_direnv_cannot_authorize_paths_with_shell_syntax(self):
        project = self.work / "$(touch BAD)"
        project.mkdir()
        self.stub("direnv", '''#!/usr/bin/env bash
[[ "$1" == version ]] || exit 99
printf '2.32.1\\n'
''')
        self.denv("-b", "venv", "-n", project, expected=1)
        self.assertFalse((project / ".envrc").exists())
        self.assertFalse((self.work / "BAD").exists())

    def test_shared_parser_and_separator(self):
        for arguments in (("status", "--force"), ("clean", "--backend", "uv"), ("init", "-b"), ("status", ".", "."), ("init", "--", ".", ".")):
            with self.subTest(arguments=arguments):
                self.denv(*arguments, expected=2)
        target = self.work / "--no-color"
        target.mkdir()
        self.denv("-b", "venv", "-n", "--", "--no-color")
        self.assertTrue((target / ".envrc").is_file())

    def test_directory_alias_configures_physical_workspace(self):
        environment = self.work / ".venv/bin"
        environment.mkdir(parents=True)
        (environment / "activate").write_text("export DENV_DIRECTORY_ALIAS=yes\n")
        alias = self.root / "alias"
        alias.symlink_to(self.work, target_is_directory=True)
        self.denv("-n", alias)
        self.denv("status", "-q", alias)
        # direnv allow canonicalizes aliases, but some versions of exec do
        # not. Test activation at the physical path used for authorization.
        self.run_command("direnv", "exec", alias.resolve(), "sh", "-c", 'test "$DENV_DIRECTORY_ALIAS" = yes')

    def test_clean_revokes_previously_authorized_custom_content(self):
        envrc = self.work / ".envrc"
        envrc.write_text("export KEEP=yes\n")
        self.run_command("direnv", "allow", self.work)
        self.denv("-b", "venv", "-n")
        self.denv("clean")
        self.assertEqual(envrc.read_text(), "export KEEP=yes\n")
        status = self.run_command("direnv", "status").stdout
        allowed = [line.split()[-1] for line in status.splitlines() if line.startswith("Found RC allowed ")]
        self.assertTrue(allowed)
        self.assertNotIn(allowed[0], {"0", "true"})

    def test_clean_when_current_content_is_already_unauthorized(self):
        self.denv("-b", "venv", "-n")
        envrc = self.work / ".envrc"
        envrc.write_text(envrc.read_text() + "export KEEP=yes\n")
        real_direnv = shutil_which("direnv", self.env["PATH"])
        self.stub("direnv", f'''#!/usr/bin/env bash
if [[ "$1" == deny ]]; then
  status_output=$({shlex.quote(real_direnv)} status)
  if ! printf '%s\\n' "$status_output" | grep -Eq '^Found RC allowed (true|0)$'; then
    printf 'current content is already unauthorized\\n' >&2
    exit 1
  fi
fi
exec {shlex.quote(real_direnv)} "$@"
''')
        self.denv("clean")
        self.assertEqual(envrc.read_text(), "export KEEP=yes\n")

    def test_failed_early_assertion_makes_suite_fail(self):
        source = (REPO / "tests/test_denv.sh").read_text()
        source = re.sub(r"^SCRIPT_DIR=.*$", "SCRIPT_DIR=" + shlex.quote(str(REPO)), source, count=1, flags=re.MULTILINE)
        source = source.replace('"denv version 1." "Version string check"', '"INTENTIONALLY_IMPOSSIBLE_EXPECTATION" "Version string check"', 1)
        result = self.run_command(BASH, "-c", source, expected=1)
        self.assertIn("Version string check", result.stderr)
        self.assertIn("1 failed", result.stdout)


def shutil_which(command, path):
    import shutil
    result = shutil.which(command, path=path)
    if result is None:
        raise RuntimeError(f"{command} not installed")
    return result


if __name__ == "__main__":
    unittest.main(verbosity=2)
