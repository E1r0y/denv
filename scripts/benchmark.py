#!/usr/bin/env python3
"""Measure complete direnv exec runs against empty and venv workspaces."""

import argparse
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=int, default=30)
    args = parser.parse_args()
    if args.runs < 5:
        parser.error("--runs must be at least 5")
    with tempfile.TemporaryDirectory(prefix="denv-bench-") as directory:
        base = Path(directory)
        user_home = base / "home"
        user_home.mkdir()
        env = dict(os.environ, HOME=str(user_home), XDG_DATA_HOME=str(user_home / "data"),
                   XDG_CONFIG_HOME=str(user_home / "config"), DIRENV_CONFIG=str(user_home / "config/direnv"),
                   DENV_ALLOW_ROOT="1", NO_COLOR="1")

        def command(*arguments):
            return subprocess.run([str(arg) for arg in arguments], env=env, check=True,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        results = {}
        for name in ("empty", "venv"):
            workspace = base / name
            workspace.mkdir()
            if name == "empty":
                (workspace / ".envrc").write_text("# empty baseline\n")
                command("direnv", "allow", workspace)
            else:
                command("python3", "-m", "venv", "--without-pip", workspace / ".venv")
                command(ROOT / "bin/denv", workspace)
            samples = []
            for run in range(args.runs + 3):
                started = time.perf_counter()
                command("direnv", "exec", workspace, "true")
                if run >= 3:
                    samples.append((time.perf_counter() - started) * 1000)
            samples.sort()
            results[name] = {"median_ms": round(statistics.median(samples), 3),
                             "p95_ms": round(samples[min(len(samples) - 1, int(len(samples) * .95))], 3)}
        results["system"] = platform.platform()
        results["direnv"] = command("direnv", "version").stdout.decode().strip()
        results["runs"] = args.runs
        print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
