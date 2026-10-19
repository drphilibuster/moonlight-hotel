#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Check that every hotel-owned file is licensed AGPL-3.0-or-later.

A tracked file passes if its first lines carry
`SPDX-License-Identifier: AGPL-3.0-or-later`, or if an annotation in REUSE.toml
covers it with that licence. Third-party trees (ninjam/upstream/ and the
licence texts) are the licence audit's job, not this one's.

Exit status is 0 when every file passes, 1 otherwise.
"""
from __future__ import annotations

import re
import subprocess
import sys
import tomllib
from pathlib import Path

LICENCE = "AGPL-3.0-or-later"
THIRD_PARTY = ("ninjam/upstream/", "LICENSES/")
EXEMPT = {"LICENSE"}
HEADER_LINES = 10
SPDX = re.compile(r"^\W*SPDX-License-Identifier:\s*([A-Za-z0-9.+\-]+)\s*$")


def glob_to_regex(pattern: str) -> re.Pattern:
    """REUSE.toml globs: `**` crosses directories, `*` doesn't."""
    out = []
    i = 0
    while i < len(pattern):
        if pattern.startswith("**", i):
            out.append(".*")
            i += 2
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    return re.compile("".join(out) + r"\Z")


def annotated(repo: Path) -> list[re.Pattern]:
    cfg = repo / "REUSE.toml"
    if not cfg.exists():
        return []
    pats = []
    for a in tomllib.loads(cfg.read_text()).get("annotations", []):
        if a.get("SPDX-License-Identifier") != LICENCE:
            continue
        paths = a["path"] if isinstance(a["path"], list) else [a["path"]]
        pats += [glob_to_regex(p) for p in paths]
    return pats


def check(repo: Path, files: list[str]) -> list[str]:
    covers = annotated(repo)
    bad = []
    for rel in files:
        if rel in EXEMPT or rel.startswith(THIRD_PARTY):
            continue
        if any(p.match(rel) for p in covers):
            continue
        try:
            head = (repo / rel).read_text(encoding="utf-8", errors="replace").splitlines()[:HEADER_LINES]
        except (OSError, IsADirectoryError):
            continue
        ids = [m.group(1) for line in head if (m := SPDX.search(line))]
        if ids != [LICENCE]:
            bad.append(f"{rel}: {'no SPDX header' if not ids else 'licensed ' + ', '.join(ids)}")
    return bad


def main() -> int:
    repo = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
    files = subprocess.check_output(["git", "ls-files"], cwd=repo, text=True).splitlines()
    bad = check(repo, files)
    for b in bad:
        print(b)
    print(f"{len(files)} tracked files checked; {len(bad)} without an {LICENCE} header or annotation")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
