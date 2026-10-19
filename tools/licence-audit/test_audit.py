# SPDX-FileCopyrightText: 2026 Moon Technologies LLC
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Tests for the licence audit. Run: python3 -m unittest tools/licence-audit/test_audit.py"""
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit  # noqa: E402

GPL2_PLUS = """/*
    Foo - foo.cpp
    Copyright (C) 2005 Somebody
    Foo is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.
*/
"""
GPL2_ONLY = """/*
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 2 of the License.
 */
"""
LGPL2_PLUS = """/* This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */
"""
ZLIB = """/*
    This software is provided 'as-is', without any express or implied
    warranty.  In no event will the authors be held liable for any damages
    arising from the use of this software.

    Permission is granted to anyone to use this software for any purpose,
    including commercial applications, and to alter it and redistribute it
    freely, subject to the following restrictions:
*/
"""
AGPL3_PLUS = """// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU Affero General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option) any
// later version.
"""


def build(files: dict[str, str]) -> Path:
    root = Path(tempfile.mkdtemp())
    for rel, text in files.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(textwrap.dedent(text))
    return root


def policy(entries, resolutions=()):
    return {
        "audit": {"roots": ["up"]},
        "policy": {"allowed": ["GPL-2.0-or-later", "LGPL-2.0-or-later", "Zlib", "AGPL-3.0-or-later"]},
        "target": [{"name": "t", "entries": entries}],
        "resolution": list(resolutions),
    }


class ClassifyText(unittest.TestCase):
    def test_gpl2_or_later(self):
        self.assertEqual(audit.classify_text(GPL2_PLUS)[0], "GPL-2.0-or-later")

    def test_gpl2_only(self):
        self.assertEqual(audit.classify_text(GPL2_ONLY)[0], "GPL-2.0-only")

    def test_lgpl_is_not_gpl(self):
        self.assertEqual(audit.classify_text(LGPL2_PLUS)[0], "LGPL-2.0-or-later")

    def test_agpl_is_not_gpl(self):
        self.assertEqual(audit.classify_text(AGPL3_PLUS)[0], "AGPL-3.0-or-later")

    def test_zlib(self):
        self.assertEqual(audit.classify_text(ZLIB)[0], "Zlib")

    def test_spdx_canonical_case(self):
        self.assertEqual(audit.classify_text("// SPDX-License-Identifier: Zlib\n")[0], "Zlib")
        self.assertEqual(audit.classify_text("# SPDX-License-Identifier: GPL-2.0-or-later\n")[0],
                         "GPL-2.0-or-later")

    def test_nothing(self):
        self.assertIsNone(audit.classify_text("#ifndef FOO_H\n#define FOO_H\n#endif\n"))


class Audit(unittest.TestCase):
    def test_closure_passes_and_follows_includes(self):
        root = build({
            "up/a.cpp": GPL2_PLUS + '#include "b.h"\n#include <stdio.h>\n',
            "up/b.h": ZLIB + '#include "sub/c.h"\n',
            "up/sub/c.h": ZLIB,
            "up/unused.cpp": GPL2_ONLY,
        })
        r = audit.Auditor(root, policy(["up/a.cpp"])).run()
        self.assertTrue(r["passed"])
        self.assertEqual(r["targets"]["t"]["files"], 3)
        # Files outside every target are reported but don't fail the audit.
        unused = next(f for f in r["files"] if f["path"] == "up/unused.cpp")
        self.assertEqual((unused["licence"], unused["targets"]), ("GPL-2.0-only", []))

    def test_gpl2_only_in_closure_fails(self):
        root = build({"up/a.cpp": GPL2_PLUS + '#include "bad.h"\n', "up/bad.h": GPL2_ONLY})
        r = audit.Auditor(root, policy(["up/a.cpp"])).run()
        self.assertFalse(r["passed"])
        self.assertEqual(r["targets"]["t"]["failures"][0]["path"], "up/bad.h")

    def test_headerless_file_fails_until_resolved(self):
        files = {"up/a.cpp": GPL2_PLUS + '#include "bare.h"\n', "up/bare.h": "int x;\n"}
        self.assertFalse(audit.Auditor(build(files), policy(["up/a.cpp"])).run()["passed"])
        res = {"paths": ["up/bare.h"], "licence": "Zlib", "reason": "test"}
        r = audit.Auditor(build(files), policy(["up/a.cpp"], [res])).run()
        self.assertTrue(r["passed"])
        bare = next(f for f in r["files"] if f["path"] == "up/bare.h")
        self.assertEqual(bare["source"], "resolution")

    def test_resolution_never_overrides_a_notice(self):
        files = {"up/a.cpp": GPL2_ONLY}
        res = {"paths": ["up/a.cpp"], "licence": "Zlib", "reason": "wrong"}
        r = audit.Auditor(build(files), policy(["up/a.cpp"], [res])).run()
        self.assertFalse(r["passed"])

    def test_see_reference(self):
        root = build({
            "up/conn.cpp": "/*\n** License: see jnetlib.h\n*/\n",
            "up/jnetlib.h": ZLIB,
            "up/deflate.c": "/* For conditions of distribution and use, see copyright notice in jnetlib.h\n */\n",
        })
        r = audit.Auditor(root, policy(["up/conn.cpp", "up/deflate.c"])).run()
        self.assertTrue(r["passed"])
        conn = next(f for f in r["files"] if f["path"] == "up/conn.cpp")
        self.assertEqual((conn["licence"], conn["source"]), ("Zlib", "see:up/jnetlib.h"))

    def test_missing_entry_is_an_error(self):
        root = build({"up/a.cpp": GPL2_PLUS})
        with self.assertRaises(SystemExit):
            audit.Auditor(root, policy(["up/missing.cpp"])).run()


if __name__ == "__main__":
    unittest.main()
