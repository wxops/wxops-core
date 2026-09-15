#!/usr/bin/env python3
"""
Release-tag helpers shared by the API-compat gate and the release tooling.

A release is named `release-YYYY-MM-DD` (UTC), with `.2`, `.3` … for a second
release on the same day. Tags cut before that switch are semver (`v0.4.0`).
Both are valid baselines, so every lookup here matches both patterns.
"""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

RELEASE_RE = re.compile(r"^release-\d{4}-\d{2}-\d{2}(\.\d+)?$")
LEGACY_RE = re.compile(r"^v\d+\.\d+\.\d+$")


def is_release_tag(name: str) -> bool:
    return bool(RELEASE_RE.match(name) or LEGACY_RE.match(name))


def git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)


def previous_tag(before: str | None = None) -> str | None:
    """The newest release tag reachable from HEAD, or from just before `before`.

    `before` exists for describing a release that is already tagged: at the
    tagged commit `git describe` returns that same tag, which is the release
    itself, not the baseline it should be compared against.
    """
    rev = f"{before}^" if before else "HEAD"
    proc = git("describe", "--tags", "--abbrev=0",
               "--match", "release-*", "--match", "v*", rev)
    tag = proc.stdout.strip()
    return tag if proc.returncode == 0 and is_release_tag(tag) else None


def tag_exists(name: str) -> bool:
    return git("rev-parse", "-q", "--verify", f"refs/tags/{name}").returncode == 0


def show(ref: str, path: str) -> str | None:
    """File content at `ref`, or None when the path did not exist there."""
    proc = git("show", f"{ref}:{path}")
    return proc.stdout if proc.returncode == 0 else None


def ls(ref: str, path: str) -> list[str]:
    """Every file under `path` at `ref`, repo-relative."""
    proc = git("ls-tree", "-r", "--name-only", ref, "--", path)
    return proc.stdout.splitlines() if proc.returncode == 0 else []
