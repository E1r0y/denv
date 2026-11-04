#!/usr/bin/env python3
"""Installer verification uses a local transport adapter, never the network."""

import hashlib
import json
from pathlib import Path
import shutil
import unittest

from support import BASH, REPO, WorkspaceTest


class InstallerTests(WorkspaceTest):
    def setUp(self):
        super().setUp()
        self.prefix = self.root / "prefix with spaces"
        self.install_script = self.root / "install.sh"
        shutil.copyfile(REPO / "install.sh", self.install_script)
        self.payload = self.root / "remote payload"
        self.payload.mkdir()
        self.commit = "a" * 40
        self.transport_log = self.root / "urls.jsonl"
        self.env.update(DENV_TEST_PAYLOAD=str(self.payload), DENV_TEST_URLS=str(self.transport_log))
        paths = ("bin/denv", "completions/bash/denv", "completions/zsh/_denv", "completions/fish/denv.fish")
        checksums = []
        for relative in paths:
            target = self.payload / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / relative, target)
            checksums.append(f"{hashlib.sha256(target.read_bytes()).hexdigest()}  {relative}\n")
        (self.payload / "checksums.sha256").write_text("".join(checksums))
        self.stub("curl", '''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
args=sys.argv[1:]
url=next(arg for arg in args if arg.startswith('https://'))
output=pathlib.Path(args[args.index('-o')+1])
with open(os.environ['DENV_TEST_URLS'], 'a') as stream: stream.write(json.dumps(url)+'\\n')
if 'api.github.com' in url:
    output.write_text('  "sha": "'+'a'*40+'",\\n')
else:
    relative='/'.join(url.split('/')[6:])
    source=pathlib.Path(os.environ['DENV_TEST_PAYLOAD'])/relative
    if not source.is_file(): sys.exit(22)
    shutil.copyfile(source, output)
''')

    def install(self, *args, **kwargs):
        return self.run_command(BASH, self.install_script, "--prefix", self.prefix, *args, **kwargs)

    def test_remote_components_use_one_commit_and_verified_payload(self):
        result = self.install()
        self.assertEqual(result.stdout, "", "installer diagnostics belong on stderr")
        self.assertEqual((self.prefix / "bin/denv").read_bytes(), (REPO / "bin/denv").read_bytes())
        urls = [json.loads(line) for line in self.transport_log.read_text().splitlines()]
        self.assertEqual(len(urls), 6)
        for url in urls[1:]:
            self.assertIn("/" + self.commit + "/", url)
        self.assertFalse(list((self.prefix / "bin").glob(".denv.*")))

    def test_corrupt_payload_preserves_existing_binary_and_cleans_temporary_files(self):
        (self.prefix / "bin").mkdir(parents=True)
        old = self.prefix / "bin/denv"
        old.write_text("old binary")
        (self.payload / "bin/denv").write_text("corrupted download")
        self.install("--force", expected=1)
        self.assertEqual(old.read_text(), "old binary")
        self.assertFalse(list((self.prefix / "bin").glob(".denv.*")))

    def test_explicit_commit_does_not_use_api(self):
        self.install("--ref", self.commit)
        self.assertNotIn("api.github.com", self.transport_log.read_text())

    def test_copy_replaces_symlink_without_modifying_its_target(self):
        old_source = self.root / "other executable"
        old_source.write_text("preserve target")
        (self.prefix / "bin").mkdir(parents=True)
        (self.prefix / "bin/denv").symlink_to(old_source)
        self.run_command(BASH, REPO / "install.sh", "--prefix", self.prefix, "--force")
        self.assertEqual(old_source.read_text(), "preserve target")
        self.assertFalse((self.prefix / "bin/denv").is_symlink())

    def test_missing_completion_is_reported_without_false_success(self):
        (self.prefix / "share/zsh/site-functions/_denv").mkdir(parents=True)
        result = self.run_command(BASH, REPO / "install.sh", "--prefix", self.prefix, expected=1)
        self.assertTrue((self.prefix / "bin/denv").is_file())
        self.assertIn("incomplete", result.stderr)
        self.assertNotIn("Installation complete:", result.stderr)

    def test_completion_write_failure_preserves_old_file_and_cleans_temporaries(self):
        completion = self.prefix / "share/bash-completion/completions/denv"
        completion.parent.mkdir(parents=True)
        completion.write_text("old completion")
        cat = shutil.which("cat")
        self.stub("cat", f'''#!/usr/bin/env bash
if [[ "$*" == *'completions/bash/denv'* ]]; then printf partial; exit 1; fi
exec {cat} "$@"
''')
        self.run_command(BASH, REPO / "install.sh", "--prefix", self.prefix, expected=1)
        self.assertEqual(completion.read_text(), "old completion")
        self.assertFalse(list(self.prefix.rglob(".denv.*")))

    def test_zdotdir_and_modular_hook_detection(self):
        user_home = Path(self.env["HOME"])
        zsh_dir = user_home / "custom zsh"
        (zsh_dir / "conf.d").mkdir(parents=True)
        (user_home / ".zshenv").write_text('export ZDOTDIR="${HOME}/custom zsh"\n')
        (zsh_dir / "conf.d/direnv.zsh").write_text('eval "$(direnv hook zsh)"\n')
        result = self.run_command(BASH, REPO / "install.sh", "--prefix", self.prefix, env={"SHELL": "/bin/zsh"})
        self.assertIn(str(zsh_dir / ".zshrc"), result.stderr)
        self.assertIn("fpath=", result.stderr)
        self.assertNotIn("Add the direnv hook", result.stderr)

    def test_fish_setup_uses_fish_syntax_and_xdg_config(self):
        result = self.run_command(BASH, REPO / "install.sh", "--prefix", self.prefix, env={"SHELL": "/usr/bin/fish"})
        self.assertIn("fish_add_path", result.stderr)
        self.assertIn(self.env["XDG_CONFIG_HOME"] + "/fish/config.fish", result.stderr)
        self.assertNotIn("export PATH=", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
