#!/usr/bin/env python3
"""Release policy crosses real Git history and a local GitHub API adapter."""

import json
import shutil
import sys
import unittest

from support import REPO, WorkspaceTest


class ReleasePolicyTests(WorkspaceTest):
    def setUp(self):
        super().setUp()
        self.run_command("git", "init", "-b", "main")
        self.run_command("git", "config", "user.name", "Test Maintainer")
        self.run_command("git", "config", "user.email", "maintainer@example.invalid")
        (self.work / "README.md").write_text("initial content\n")
        self.run_command("git", "add", "README.md")
        self.run_command("git", "commit", "--no-gpg-sign", "-m", "Initial fixture")
        self.sha = self.run_command("git", "rev-parse", "HEAD").stdout.strip()
        self.run_command("git", "update-ref", "refs/remotes/origin/main", self.sha)
        self.script = self.work / "scripts/verify_release.py"
        self.script.parent.mkdir()
        shutil.copyfile(REPO / "scripts/verify_release.py", self.script)
        self.response = self.root / "response.json"
        self.env["DENV_TEST_RELEASE_RESPONSE"] = str(self.response)
        self.env["DENV_TEST_API_CALLED"] = str(self.root / "api-called")
        self.stub("gh", '''#!/usr/bin/env python3
import os, pathlib, sys
pathlib.Path(os.environ['DENV_TEST_API_CALLED']).write_text(' '.join(sys.argv[1:]))
print(pathlib.Path(os.environ['DENV_TEST_RELEASE_RESPONSE']).read_text())
''')

    def check_policy(self, runs, commit=None, expected=0):
        self.response.write_text(json.dumps({"workflow_runs": runs}))
        return self.run_command(sys.executable, self.script, "--commit", commit or self.sha,
                                "--repository", "example/project", expected=expected)

    def successful_run(self, **overrides):
        return {"head_sha": self.sha, "head_branch": "main", "event": "push",
                "status": "completed", "conclusion": "success",
                "html_url": "https://github.com/example/project/actions/runs/123", **overrides}

    def test_accepts_main_commit_with_successful_main_ci(self):
        result = self.check_policy([self.successful_run()])
        self.assertEqual(json.loads(result.stdout)["commit"], self.sha)
        request = (self.root / "api-called").read_text()
        self.assertIn("actions/workflows/ci.yml/runs", request)
        self.assertIn("head_sha=" + self.sha, request)

    def test_rejects_wrong_commit_branch_event_or_ci_state(self):
        cases = [{"head_sha": "0" * 40}, {"head_branch": "feature"}, {"event": "pull_request"},
                 {"status": "in_progress"}, {"conclusion": "failure"}]
        for change in cases:
            with self.subTest(change=change):
                result = self.check_policy([self.successful_run(**change)], expected=1)
                self.assertIn("successful push CI on main", result.stderr)
        self.check_policy([], expected=1)

    def test_rejects_unmerged_branch_before_calling_api(self):
        self.run_command("git", "switch", "-c", "unmerged")
        (self.work / "README.md").write_text("unmerged content\n")
        self.run_command("git", "add", "README.md")
        self.run_command("git", "commit", "--no-gpg-sign", "-m", "Unmerged fixture")
        commit = self.run_command("git", "rev-parse", "HEAD").stdout.strip()
        result = self.check_policy([self.successful_run(head_sha=commit)], commit=commit, expected=1)
        self.assertIn("must belong to origin/main", result.stderr)
        self.assertFalse((self.root / "api-called").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
