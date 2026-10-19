# NINJAM licence audit

**Question.** Is NINJAM's source GPLv2-only anywhere the hotel builds from it, or
is it GPLv2-or-later throughout? Every client and server component depends on
the answer: JUCE is AGPLv3, and a GPLv2-only file can't be combined with it.

**Answer.** Everything the hotel builds from NINJAM is **GPL-2.0-or-later or
Zlib**. No file in either link set is GPLv2-only. The hotel takes the "or later"
option to use NINJAM under GPLv3, and GPLv3 §13 permits combining it with AGPLv3
code. The combined works (ninjamsrv, the plugin, the Moonlight app, mixbot and
moonlight-bot) are distributed under AGPL-3.0-or-later.

| | |
| --- | --- |
| Upstream | https://github.com/justinfrankel/ninjam |
| Commit audited | `f4c0eff3a1d8d5f3ead470d0c7405c3ee37da24e` (2025-06-01), at `ninjam/upstream/` |
| Tool | `tools/licence-audit/audit.py` with `tools/licence-audit/policy.toml` (runs in CI) |
| Machine report | [ninjam-audit.json](ninjam-audit.json), [ninjam-audit.generated.md](ninjam-audit.generated.md) (every file) |
| Date | 2026-10-18 |

## Method

1. Every file under `ninjam/upstream/` is classified by the licence notice it
   states itself (SPDX tags, GPL/LGPL/AGPL notices with their version clause,
   Zlib, MIT, BSD, ISC, IJG, libpng, public domain). Notices that point
   elsewhere — "License: see jnetlib.h", "For conditions of distribution and
   use, see copyright notice in zlib.h", "See lice.h for license" — are
   followed to the file they name.
2. The GPL rules distinguish "version 2 of the License, or (at your option) any
   later version" (GPL-2.0-or-later) from "version 2 of the License"
   (GPL-2.0-only). They never match inside a Lesser, Library or Affero notice.
3. Two **link sets** are defined from upstream's own build. For the server
   that is the `OBJS` list in `ninjam/server/Makefile`; for the client core it
   is `njclient.cpp`, `mpb.cpp` and `netmsg.cpp` plus the WDL sources they call.
   The audit follows every `#include "…"` from those entries, and the
   resulting closure is what gets compiled and linked.
4. A link set fails if any file in its closure has a licence outside the
   policy's allowlist, or has no determinable licence and no recorded
   resolution. A resolution can only fill in a file that states nothing; it
   can never override a notice a file carries.

## Results

| Link set | Files | Licences | Result |
| --- | --- | --- | --- |
| `ninjamsrv` | 34 | 27 Zlib (WDL, jnetlib), 7 GPL-2.0-or-later (NINJAM) | **Pass** |
| `njclient-core` | 39 | 33 Zlib (WDL, jnetlib), 6 GPL-2.0-or-later (NINJAM) | **Pass** |

Every NINJAM file in either set — `njclient.{cpp,h}`, `mpb.{cpp,h}`,
`netmsg.{cpp,h}`, `server/ninjamsrv.cpp`, `server/usercon.{cpp,h}` — carries
Cockos's notice: *"either version 2 of the License, or (at your option) any
later version."*

### Resolutions (files with no notice of their own)

Six WDL headers in the link sets carry no notice: `assocarray.h`,
`mergesort.h`, `utf8_extended.h`, `wdltypes.h`, `wdlatomic.h` and
`win32_utf8.h`. They are resolved as **Zlib**. Cockos states on
https://www.cockos.com/wdl/ that WDL is distributed under its zlib-style
licence, with only the bundled third-party libraries (JNetLib, LibPNG, GifLib,
JPEGLib, zlib) differing, and those are "similarly licensed". Every WDL file
that does carry a notice carries that licence.

This resolution rests on Cockos's public statement, not on per-file notices.
That is sound, but a one-line written confirmation from Cockos would make it
airtight. Asking for one is optional and outward-facing; it isn't done.

### One file removed rather than resolved

The first run found `ninjam/winclient/old_jesusonic_dll.h` in the client
closure. It carries a Cockos copyright line but no licence. It is reached only
through `njmisc.h`, which holds client-UI utilities and the Jesusonic effect
interface. `njclient` doesn't use `njmisc` at all. `njmisc` left with the
upstream clients (below), so the file is out of the closure and the question
doesn't arise.

## What was removed from the tree

The hotel's own clients are the only way into a room, so upstream's clients
were removed from `ninjam/upstream/` in the commit after the import. History
keeps them for provenance. The full list is in [ninjam/README.md](../../ninjam/README.md):
ReaNINJAM (`jmde/`), the Cocoa, curses, Windows and GUI clients, ninjamcast,
the ASIO and kernel-streaming drivers, and client-only audio I/O, mixer and
utility files.

## The rest of the tree (not built by the hotel)

These are classified and reported but don't affect the result, because nothing
the hotel ships links them:

| Area | Licence found |
| --- | --- |
| WDL core, EEL2, LICE, SWELL, wingui, localize | Zlib (mostly by notice; many small headers headerless, covered by the WDL statement above) |
| WDL/zlib | Zlib (via `zlib.h`) |
| WDL/jpeglib | IJG (via its README's LEGAL ISSUES) |
| WDL/libpng | libpng-2.0 (PNG Reference Library License v2, via `png.h`) |
| WDL/giflib | MIT (`COPYING`); headerless source files not individually determinable |
| WDL/lice/glew | MIT and BSD-2-Clause |
| `WDL/swell/gtkimcontextsimpleseqs.h` | LGPL-2.0-or-later (from GTK) |
| `WDL/MersenneTwister.h` | BSD-2-Clause |
| `ninjam/autosong`, `ninjam/cliplogcvt` | GPL-2.0-or-later (offline tools) |
| `WDL/eel2/*.o`, `*.obj` | Prebuilt object files; never linked by the hotel |

If a later milestone starts building anything here, adding it to a link set in
`policy.toml` puts it under the same gate.

### The server's connect agreement

`ninjam/server/cclicense.txt` is the agreement upstream's server shows on
connect, putting every jam under CC BY-NC-SA 2.5. The hotel server doesn't use
it. The design has the hotel set no licence on music: each room's host picks
one, and it is recorded in the room's manifest. The hotel replaces this
agreement with its own terms acceptance and per-room rights confirmation (M1).
`server/license.txt` is the GPLv2 text.

## Obligations this creates

- Keep every upstream notice intact. The GPL and the zlib licence both require it.
- Mark every modified upstream file. GPLv2 §2a, GPLv3 §5a and the zlib
  licence's "altered source versions must be plainly marked" all require it.
  The hotel adds a "Modified by Moon Technologies LLC" line under the original
  notice (see CONTRIBUTING.md).
- Ship complete corresponding source for every binary and network service.
  This is AGPLv3 §13 for the services; each one reports its build commit.
- The CLA can't relicense NINJAM-derived code; CONTRIBUTING.md says so.

## Dependencies not in the tree yet

`vorbisencdec.h` includes libvorbis and libogg (BSD-3-Clause) from the system
include path, so they aren't part of this tree. M1 vendors them (with FLAC,
Opus and mbedTLS) and adds them to the audit's roots and link sets in the same
change, so the gate covers them from their first commit.

## Other M0 licence checks

| Item | Finding | Source |
| --- | --- | --- |
| JUCE 9.0.3 | Modules dual-licensed **AGPLv3** or commercial; examples ISC; third-party inventory in `JUCE.spdx.json` | JUCE `LICENSE.md` at tag 9.0.3 |
| CLAP in JUCE 9.0.3 | **Not native.** No CLAP code in the 9.0.3 tree, so the plugin uses clap-juce-extensions (MIT) | JUCE git tree at 9.0.3 |
| AcoustID server | MIT | acoustid/acoustid-server |
| AcoustID index (`acoustid-index`) | **No licence**, so all rights reserved. It can't be self-hosted. **Design change:** the hotel builds its own fingerprint index (a works job, M5) from the data dumps, matched with Chromaprint | acoustid/acoustid-index (no LICENSE file) |
| AcoustID data | CC BY-SA 3.0 (the MusicBrainz mapping is CC0). Dumps are daily incremental JSON at data.acoustid.org and include fingerprints. Obligations: attribution, and ShareAlike if the hotel distributes the derived index | acoustid.org/database |
| Chromaprint | MIT for its own code, LGPL-2.1 as a whole (bundled FFmpeg parts). Compatible | acoustid/chromaprint `LICENSE.md` |
| AAX SDK terms for an AGPL plugin | **Open.** Avid's SDK licence sits behind the developer account | needs the LLC's Avid developer login |
| NDI SDK terms for the helper process | **Open.** Review alongside the helper's linking exception | NDI SDK licence |
| Transmittal Syphon code (James Frontz, GPL-3.0-or-later) | **Open.** James licenses it to the LLC under the CLA before it enters the monorepo (M4) | — |
