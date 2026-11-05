#!/usr/bin/env python3
"""Require a release commit to belong to main and have successful main CI."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.run(args, cwd=ROOT, text=True, capture_output=True, check=True).stdout.strip()


def verify(commit, repository):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid GitHub repository")
    sha = run("git", "rev-parse", "--verify", "--end-of-options", commit + "^{commit}")
    ancestor = subprocess.run(["git", "merge-base", "--is-ancestor", sha, "origin/main"], cwd=ROOT)
    if ancestor.returncode != 0:
        raise ValueError("The release commit must belong to origin/main")
    response = run("gh", "api", "--method", "GET", f"repos/{repository}/actions/workflows/ci.yml/runs",
                   "-f", f"head_sha={sha}", "-f", "branch=main", "-f", "event=push", "-f", "status=success")
    for item in json.loads(response)["workflow_runs"]:
        if (item.get("head_sha") == sha and item.get("head_branch") == "main"
                and item.get("event") == "push" and item.get("status") == "completed"
                and item.get("conclusion") == "success"):
            return {"commit": sha, "ci_run": item["html_url"]}
    raise ValueError("The release commit must have successful push CI on main")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commit", default=os.environ.get("GITHUB_SHA"))
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"))
    args = parser.parse_args()
    if not args.commit or not args.repository:
        parser.error("--commit and --repository are required outside GitHub Actions")
    try:
        result = verify(args.commit, args.repository)
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) and error.stderr else str(error)
        print(f"Release verification failed: {detail}", file=sys.stderr)
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
