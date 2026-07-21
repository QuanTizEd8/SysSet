"""Resolve GitHub credentials for test subprocesses and containers."""

from __future__ import annotations

import os
import shutil
import subprocess


def ensure_github_token() -> bool:
    """Populate ``GITHUB_TOKEN`` from the standard available credentials.

    Test containers consume ``GITHUB_TOKEN``.  Developers commonly authenticate
    through ``gh`` instead of exporting that variable, while some automation
    provides the equivalent ``GH_TOKEN`` variable.  Normalize either source
    before Docker builds or containers are launched.

    Return whether a non-empty token is available.  Failure is deliberately
    silent so tests that do not require GitHub authentication remain runnable.
    """
    if os.environ.get("GITHUB_TOKEN"):
        return True

    gh_token = os.environ.get("GH_TOKEN")
    if gh_token:
        os.environ["GITHUB_TOKEN"] = gh_token
        return True

    if shutil.which("gh") is None:
        return False
    try:
        result = subprocess.run(
            ["gh", "auth", "token"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
    except OSError:
        return False

    token = result.stdout.strip()
    if result.returncode != 0 or not token or any(char.isspace() for char in token):
        return False
    os.environ["GITHUB_TOKEN"] = token
    return True
