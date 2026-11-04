#!/usr/bin/env python3
"""Command adapters for offline backend contract tests; unknown calls fail."""

import json
import os
from pathlib import Path
import shlex
import sys


name = Path(sys.argv[0]).name
args = sys.argv[1:]
target = Path(os.environ["DENV_TEST_ENV"])
with open(os.environ["DENV_TEST_CALLS"], "a") as stream:
    stream.write(json.dumps([name, *args]) + "\n")


def create(prefix, conda=False):
    prefix.mkdir(parents=True, exist_ok=True)
    if os.environ.get("DENV_TEST_FAIL_CREATE"):
        (prefix / "partial").touch()
        sys.exit(42)
    (prefix / "bin").mkdir(exist_ok=True)
    interpreter = prefix / "bin" / "python3"
    if not interpreter.exists():
        interpreter.symlink_to(sys.executable)
    (prefix / "bin" / "activate").write_text(
        f"export VIRTUAL_ENV={shlex.quote(str(prefix))}\n"
        f"export PATH={shlex.quote(str(prefix / 'bin'))}:$PATH\n"
    )
    if conda:
        (prefix / "conda-meta").mkdir(exist_ok=True)


if name == "uv" and args[:1] == ["venv"]:
    create(Path(args[-1]))
elif name in {"poetry", "pipenv", "pdm", "hatch"}:
    queries = {
        "poetry": ["env", "info", "--path"],
        "pipenv": ["--venv"],
        "pdm": ["venv", "--path", "in-project"],
        "hatch": ["env", "find", "default"],
    }
    if args == queries[name]:
        if not (target / "bin" / "activate").is_file():
            sys.exit(1)
        print(target)
    elif (name == "poetry" and args[:2] == ["env", "use"]) or (
        name == "pipenv" and args[:1] == ["--python"]
    ) or (name == "pdm" and args[:2] == ["venv", "create"]) or (
        name == "hatch" and args == ["env", "create", "default"]
    ):
        create(target)
    elif name == "pdm" and args == ["info", "--python"]:
        print(target / "bin" / "python3")
    else:
        sys.exit(f"Unexpected {name} command: {args!r}")
elif name in {"conda", "mamba", "micromamba"}:
    if args[:2] == ["env", "create"] or args[:1] == ["create"]:
        create(Path(args[args.index("--prefix") + 1]), conda=True)
    elif args == ["shell", "hook", "--shell", "bash"] or args == ["shell.bash", "hook"]:
        print(f'{name}() {{ [[ "$1" == activate ]] || return 2; export CONDA_PREFIX="$2"; export PATH="$2/bin:$PATH"; }}')
    else:
        sys.exit(f"Unexpected {name} command: {args!r}")
elif name == "pixi":
    if args == ["install"]:
        create(Path.cwd() / ".pixi/envs/default", conda=True)
    elif args == ["shell-hook", "--shell", "bash", "--frozen", "--no-install"]:
        prefix = Path.cwd() / ".pixi/envs/default"
        if not (prefix / "conda-meta").is_dir():
            sys.exit(1)
        print(f"export CONDA_PREFIX={shlex.quote(str(prefix))}")
        print(f"export PATH={shlex.quote(str(prefix / 'bin'))}:$PATH")
    else:
        sys.exit(f"Unexpected pixi command: {args!r}")
else:
    sys.exit(f"Unknown backend command: {name} {args!r}")
