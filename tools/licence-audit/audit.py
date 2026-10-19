#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Licence audit for third-party trees in The Moonlight Hotel.

Classifies every file under the audited roots by the licence its own notice
states, follows "License: see <file>" references, and computes the include
closure of each build target named in policy.toml. A target fails the audit if
any file in its closure has a licence the policy doesn't allow to combine with
AGPL-3.0-or-later, or has no determinable licence and no recorded resolution.

Files outside every target are classified and reported but don't fail the
audit: they aren't linked into anything the hotel ships.

Usage:
    audit.py [--policy PATH] [--json OUT] [--markdown OUT] [--repo ROOT]

Exit status is 0 when every target passes, 1 otherwise.
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import sys
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

HEAD_BYTES = 8192  # licence notices sit at the top of a source file
REF_BYTES = 131072  # a referenced licence file (README, LICENSE, foo.h) is read further

# Ordered: the first matching rule wins, so narrower statements come first.
# Each pattern is matched against the file head with whitespace collapsed and
# comment punctuation removed, case-insensitively.
_GPL = r"(?<!lesser )(?<!library )(?<!affero )general public license"

NOTICE_RULES: list[tuple[str, str]] = [
    (r"spdx-license-identifier:\s*([a-z0-9.+\- ()]+?)(?:\s|$)", "SPDX"),
    (r"gnu affero general public license.{0,200}version 3.{0,80}any later version", "AGPL-3.0-or-later"),
    (r"gnu lesser general public license.{0,200}version 3.{0,80}any later version", "LGPL-3.0-or-later"),
    (r"gnu lesser general public license.{0,200}version 2\.1.{0,80}any later version", "LGPL-2.1-or-later"),
    (r"gnu library general public license.{0,200}version 2.{0,80}any later version", "LGPL-2.0-or-later"),
    (r"gnu lesser general public license.{0,200}version 2 of the license,? or.{0,40}any later version",
     "LGPL-2.0-or-later"),
    (r"gnu lesser general public license.{0,200}version 2\.1", "LGPL-2.1-only"),
    (r"gnu library general public license.{0,200}version 2", "LGPL-2.0-only"),
    (_GPL + r".{0,200}version 3 of the license,? or.{0,40}any later version", "GPL-3.0-or-later"),
    (_GPL + r".{0,200}version 2 of the license,? or.{0,40}any later version", "GPL-2.0-or-later"),
    (_GPL + r".{0,200}version 3 of the license", "GPL-3.0-only"),
    (_GPL + r".{0,200}version 2 of the license", "GPL-2.0-only"),
    (r"licensed under the apache license,? version 2\.0", "Apache-2.0"),
    (r"png reference library license version 2", "libpng-2.0"),
    (r"permission is hereby granted to use, copy, modify, and distribute this software"
     r" \(or portions thereof\) for any purpose, without fee", "IJG"),
    (r"provided ['\"]?as-is['\"]?,? without any express or implied warranty.{0,400}"
     r"permission is granted to anyone to use this software for any purpose", "Zlib"),
    (r"permission is hereby granted, free of charge, to any person obtaining a copy", "MIT"),
    (r"permission to use, copy, modify, and/?or distribute this software for any purpose"
     r" with or without fee is hereby granted", "ISC"),
    (r"redistribution and use in source and binary forms.{0,1200}neither the name", "BSD-3-Clause"),
    (r"redistribution and use in source and binary forms", "BSD-2-Clause"),
    (r"placed in the public domain|released into the public domain|is in the public domain"
     r"|dedicated to the public domain", "LicenseRef-PublicDomain"),
]

# "License: see jnetlib.h", "see LICENSE for terms", "license information in foo.h"
_REF_FILE = r"([A-Za-z0-9_./\-]+\.(?:h|hpp|c|cpp|txt|md)|LICENSE[A-Za-z0-9_.\-]*|COPYING[A-Za-z0-9_.\-]*|README)"
SEE_REFS = [
    # "License: see jnetlib.h"
    re.compile(r"licen[cs]e\s*(?:information|terms|details)?\s*[:\-]?\s*(?:see|in|is in)\s+" + _REF_FILE,
               re.IGNORECASE),
    # zlib, IJG, libpng: "For conditions of distribution and use, see copyright notice in zlib.h"
    re.compile(r"conditions of distribution and use,?\s+see\s+(?:the\s+)?(?:accompanying\s+)?"
               r"(?:disclaimer\s+and\s+license\s+in\s+|copyright\s+notice\s+in\s+)?" + _REF_FILE,
               re.IGNORECASE),
    # LICE: "See lice.h for license and other information"
    re.compile(r"see\s+" + _REF_FILE + r"\s+for\s+licen[cs]e", re.IGNORECASE),
]

INCLUDE = re.compile(r'^\s*#\s*(?:include|import)\s+"([^"]+)"', re.MULTILINE)

BINARY_EXT = {
    ".png", ".ico", ".icns", ".gif", ".jpg", ".jpeg", ".bmp", ".nib", ".o", ".obj",
    ".a", ".lib", ".dll", ".exe", ".dylib", ".so", ".zip", ".wav", ".ogg", ".tiff",
}


@dataclass
class FileResult:
    path: str
    licence: str            # SPDX expression, "NONE" or "BINARY"
    source: str             # how it was determined: notice | see:<file> | resolution | none
    evidence: str = ""
    targets: list[str] = field(default_factory=list)


def normalise(text: str) -> str:
    text = re.sub(r"[*#/;!]+", " ", text)          # comment punctuation
    text = re.sub(r"\s+", " ", text)
    return text.lower()


def read_head(path: Path, limit: int = HEAD_BYTES) -> str | None:
    try:
        data = path.read_bytes()[:limit]
    except OSError:
        return None
    if b"\0" in data:
        return None
    return data.decode("utf-8", errors="replace")


# Canonical spelling of the identifiers the hotel's trees use, keyed by lower case
# (classification runs on lower-cased text).
KNOWN_SPDX = [
    "AGPL-3.0-or-later", "AGPL-3.0-only", "GPL-3.0-or-later", "GPL-3.0-only",
    "GPL-2.0-or-later", "GPL-2.0-only", "LGPL-3.0-or-later", "LGPL-3.0-only",
    "LGPL-2.1-or-later", "LGPL-2.1-only", "LGPL-2.0-or-later", "LGPL-2.0-only",
    "Apache-2.0", "MIT", "ISC", "Zlib", "Libpng", "libpng-2.0", "IJG", "BSD-2-Clause", "BSD-3-Clause",
    "BSL-1.0", "CC0-1.0", "Unlicense", "MPL-2.0", "LicenseRef-PublicDomain",
]
_CANON = {k.lower(): k for k in KNOWN_SPDX}


def canonical_spdx(expr: str) -> str:
    return " ".join(_CANON.get(tok, tok) for tok in expr.split())


def classify_text(head: str) -> tuple[str, str] | None:
    flat = normalise(head)
    for pattern, licence in NOTICE_RULES:
        m = re.search(pattern, flat)
        if m:
            if licence == "SPDX":
                return canonical_spdx(m.group(1).strip()), m.group(0)
            return licence, m.group(0)[:160]
    return None


class Auditor:
    def __init__(self, repo: Path, policy: dict):
        self.repo = repo
        self.policy = policy
        self.results: dict[str, FileResult] = {}
        self.ref_results: dict[str, FileResult] = {}  # deep reads, not reported per file
        self.resolutions: dict[str, dict] = {}
        for r in policy.get("resolution", []):
            for pat in r["paths"]:
                self.resolutions[pat] = r

    # -- classification --------------------------------------------------
    def resolution_for(self, rel: str) -> dict | None:
        for pat, r in self.resolutions.items():
            if fnmatch.fnmatch(rel, pat):
                return r
        return None

    def classify(self, rel: str, seen: frozenset[str] = frozenset()) -> FileResult:
        # A file reached through a "see X" reference is read further, because
        # licence files and big headers state their terms below the top.
        key = rel if not seen else f"{rel}#ref"
        cache = self.ref_results if seen else self.results
        if key in cache:
            return cache[key]
        path = self.repo / rel
        res = self.resolution_for(rel)
        limit = REF_BYTES if seen else HEAD_BYTES
        head = None if path.suffix.lower() in BINARY_EXT else read_head(path, limit)
        found = classify_text(head) if head else None
        if found:
            result = FileResult(rel, found[0], "notice", found[1])
        else:
            ref = next((m for m in (r.search(head) for r in SEE_REFS) if m), None) if head else None
            target = self._resolve_ref(rel, ref.group(1)) if ref else None
            if target and target not in seen:
                inner = self.classify(target, seen | {rel})
                result = FileResult(rel, inner.licence, f"see:{target}", ref.group(0))
            elif head is None:
                result = FileResult(rel, "BINARY", "none")
            else:
                result = FileResult(rel, "NONE", "none")
        # A recorded resolution only fills in files with no determinable notice;
        # it never overrides what a file says about itself.
        if res and result.licence in ("NONE", "BINARY"):
            result = FileResult(rel, res["licence"], "resolution", res["reason"])
        if seen:
            self.ref_results[key] = result
        else:
            self.results[key] = result
        return result

    def _resolve_ref(self, rel: str, name: str) -> str | None:
        here = (self.repo / rel).parent
        for base in (here, here.parent, self.repo / Path(rel).parts[0]):
            cand = (base / name).resolve()
            try:
                rel_c = str(cand.relative_to(self.repo.resolve()))
            except ValueError:
                continue
            if cand.is_file():
                return rel_c
        return None

    # -- build closure ---------------------------------------------------
    def closure(self, entries: list[str], include_dirs: list[str]) -> set[str]:
        todo = list(entries)
        out: set[str] = set()
        while todo:
            rel = todo.pop()
            if rel in out:
                continue
            path = self.repo / rel
            if not path.is_file():
                raise SystemExit(f"build target names a missing file: {rel}")
            out.add(rel)
            text = path.read_text(encoding="utf-8", errors="replace")
            for inc in INCLUDE.findall(text):
                hit = self._find_include(path.parent, inc, include_dirs)
                if hit and hit not in out:
                    todo.append(hit)
        return out

    def _find_include(self, here: Path, inc: str, include_dirs: list[str]) -> str | None:
        root = self.repo.resolve()
        for base in [here] + [self.repo / d for d in include_dirs]:
            cand = (base / inc).resolve()
            if cand.is_file():
                try:
                    return str(cand.relative_to(root))
                except ValueError:
                    return None
        return None  # system or generated header: not part of the audited tree

    # -- run -------------------------------------------------------------
    def run(self) -> dict:
        allowed = set(self.policy["policy"]["allowed"])
        for root in self.policy["audit"]["roots"]:
            for dirpath, dirnames, filenames in os.walk(self.repo / root):
                dirnames[:] = [d for d in dirnames if d != ".git"]
                for f in filenames:
                    rel = str((Path(dirpath) / f).relative_to(self.repo))
                    self.classify(rel)

        targets = {}
        for t in self.policy.get("target", []):
            files = self.closure(t["entries"], t.get("include_dirs", []))
            failures = []
            for rel in sorted(files):
                r = self.classify(rel)
                r.targets.append(t["name"])
                if r.licence not in allowed:
                    failures.append({"path": rel, "licence": r.licence, "source": r.source})
            targets[t["name"]] = {
                "description": t.get("description", ""),
                "files": len(files),
                "licences": count(self.classify(f).licence for f in files),
                "failures": failures,
            }

        return {
            "roots": self.policy["audit"]["roots"],
            "allowed": sorted(allowed),
            "summary": count(r.licence for r in self.results.values()),
            "targets": targets,
            "files": [vars(r) for r in sorted(self.results.values(), key=lambda r: r.path)],
            "passed": all(not t["failures"] for t in targets.values()),
        }


def count(items) -> dict[str, int]:
    out: dict[str, int] = {}
    for i in items:
        out[i] = out.get(i, 0) + 1
    return dict(sorted(out.items(), key=lambda kv: (-kv[1], kv[0])))


def markdown(report: dict) -> str:
    lines = ["# Licence audit — generated", "",
             "Generated by `tools/licence-audit/audit.py`; do not edit by hand.", "",
             f"Result: **{'PASS' if report['passed'] else 'FAIL'}**", "",
             "## Build targets", ""]
    for name, t in report["targets"].items():
        status = "pass" if not t["failures"] else f"**{len(t['failures'])} failing**"
        lines += [f"### `{name}` — {status}", "", t["description"], "",
                  f"{t['files']} files in the include closure.", "",
                  "| Licence | Files |", "| --- | --- |"]
        lines += [f"| {k} | {v} |" for k, v in t["licences"].items()]
        if t["failures"]:
            lines += ["", "| Failing file | Licence | Determined by |", "| --- | --- | --- |"]
            lines += [f"| `{f['path']}` | {f['licence']} | {f['source']} |" for f in t["failures"]]
        lines.append("")
    lines += ["## Whole tree", "", "| Licence | Files |", "| --- | --- |"]
    lines += [f"| {k} | {v} |" for k, v in report["summary"].items()]
    lines += ["", "## Every file", "", "| File | Licence | Determined by | In targets |",
              "| --- | --- | --- | --- |"]
    for f in report["files"]:
        lines.append(f"| `{f['path']}` | {f['licence']} | {f['source']} | "
                     f"{', '.join(f['targets']) or '—'} |")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    here = Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--repo", type=Path, default=here.parent.parent)
    ap.add_argument("--policy", type=Path, default=here / "policy.toml")
    ap.add_argument("--json", type=Path)
    ap.add_argument("--markdown", type=Path)
    args = ap.parse_args(argv)

    policy = tomllib.loads(args.policy.read_text())
    report = Auditor(args.repo, policy).run()
    if args.json:
        args.json.write_text(json.dumps(report, indent=2) + "\n")
    if args.markdown:
        args.markdown.write_text(markdown(report))

    for name, t in report["targets"].items():
        state = "PASS" if not t["failures"] else "FAIL"
        print(f"{state} {name}: {t['files']} files, {t['licences']}")
        for f in t["failures"]:
            print(f"     {f['path']}: {f['licence']} ({f['source']})")
    print("whole tree:", report["summary"])
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
