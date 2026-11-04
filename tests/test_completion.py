#!/usr/bin/env python3
"""Exercise actual completion engines, including Zsh's interactive ZLE."""

import os
import pty
import select
import shutil
import signal
import time
import unittest

from support import BASH, REPO, WorkspaceTest


class CompletionTests(WorkspaceTest):
    def test_bash_backend_options_and_separator(self):
        script = r'''
set -eu
source "$1"
COMP_WORDS=(denv --backend p); COMP_CWORD=2
_denv_completions
printf '%s\n' "${COMPREPLY[@]}"
COMP_WORDS=(denv status --n); COMP_CWORD=2
_denv_completions
printf 'STATUS:%s\n' "${COMPREPLY[*]-}"
COMP_WORDS=(denv -- --n); COMP_CWORD=2
_denv_completions
printf 'SEPARATOR:%s\n' "${COMPREPLY[*]-}"
'''
        result = self.run_command(BASH, "-c", script, "completion-test", REPO / "completions/bash/denv")
        self.assertIn("poetry\n", result.stdout)
        self.assertIn("pdm\n", result.stdout)
        self.assertIn("STATUS:--no-color\n", result.stdout)
        self.assertIn("SEPARATOR:\n", result.stdout)

    @unittest.skipUnless(shutil.which("zsh"), "Zsh is not installed")
    def test_zsh_subcommands_directories_and_backends(self):
        (self.work / "unique_directory").mkdir()
        pid, master = pty.fork()
        if pid == 0:
            os.chdir(self.work)
            environment = self.env | {"TERM": "xterm", "ZDOTDIR": self.env["HOME"]}
            os.execve(shutil.which("zsh"), ["zsh", "-f", "-i"], environment)

        def receive(timeout=0.15):
            chunks = []
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                readable, _, _ = select.select([master], [], [], max(0, deadline - time.monotonic()))
                if readable:
                    chunks.append(os.read(master, 65536).decode(errors="replace"))
            return "".join(chunks)

        def wait_for_file(path):
            deadline = time.monotonic() + 5
            while not path.exists() and time.monotonic() < deadline:
                receive(0.05)
            self.assertTrue(path.exists(), "ZLE did not capture the completed command")

        try:
            receive()
            capture = self.root / "buffer"
            ready = self.root / "ready"
            setup = (
                f"PROMPT='test> '; fpath=({REPO}/completions/zsh $fpath); "
                "autoload -Uz compinit; compinit -D -i; unsetopt BEEP; bindkey -e; "
                f"_capture() {{ print -r -- \"$BUFFER\" > {capture}; BUFFER=''; CURSOR=0; zle reset-prompt; }}; "
                f"zle -N _capture; bindkey '^X' _capture; print ready > {ready}\n"
            )
            os.write(master, setup.encode())
            wait_for_file(ready)
            for command in ("denv", "denv init", "denv status", "denv clean", "denv --no-color status"):
                with self.subTest(command=command):
                    capture.unlink(missing_ok=True)
                    os.write(master, (command + " ./unique_direc\t\x18").encode())
                    wait_for_file(capture)
                    self.assertIn("./unique_directory/", capture.read_text())
                    receive()
            capture.unlink()
            os.write(master, b"denv --backend poe\t\x18")
            wait_for_file(capture)
            self.assertIn("poetry", capture.read_text())
        finally:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
            os.close(master)

    @unittest.skipUnless(shutil.which("fish"), "Fish is not installed")
    def test_fish_completions(self):
        source = REPO / "completions/fish/denv.fish"
        result = self.run_command("fish", "--no-config", "-c", 'source "$argv[1]"; complete -C "denv --backend po"; complete -C "denv status --q"', source)
        self.assertIn("poetry", result.stdout)
        self.assertIn("--quiet", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
