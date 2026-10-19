# Contributing to The Moonlight Hotel

Thank you for helping build the hotel.

## Contributor Licence Agreement

Every pull request from someone other than Moon Technologies LLC needs a signed
CLA before it can be merged. The CLA bot asks on your first pull request; you
sign by replying with the sentence it gives you, and the signature is recorded
in this repository's `cla-signatures` branch.

- Individuals: [CLA.md](CLA.md)
- Companies contributing employees' work: [CLA-ENTITY.md](CLA-ENTITY.md)

### What the CLA does and doesn't allow

You keep the copyright in your contribution. You grant Moon Technologies LLC a
licence broad enough to release your contribution under licences other than the
AGPLv3 in future.

That option only exists for parts of the hotel with no third-party copyleft in
them. Code derived from or linked with NINJAM (GPL-2.0-or-later), JUCE
(AGPLv3), Ableton Link (GPL-2.0-or-later) or other copyleft works can only ever
be distributed under the terms those works allow, whatever the CLA says. Today
that means the plugin, the Moonlight app, `ninjam/` and `mixbot` stay AGPLv3;
the front desk, lobby, housekeeper, doorman, delayline, switcher and works jobs
are the parts a future dual licence could cover.

## Licence headers

Every file the hotel writes starts with an SPDX header:

    // SPDX-FileCopyrightText: 2026 Moon Technologies LLC
    // SPDX-License-Identifier: AGPL-3.0-or-later

Files that can't carry a comment are covered by `REUSE.toml`. Upstream
third-party files keep their original headers; when the hotel modifies one, it
adds a line under the original notice:

    Modified by Moon Technologies LLC, <year>: <what changed>. Distributed as
    part of The Moonlight Hotel under AGPL-3.0-or-later.

CI runs `reuse lint` and the licence audit on every pull request.

## Third-party clients

The hotel's own clients are the only way into a hotel room. Don't add support
for, or tests that depend on, JamTaba, ReaNINJAM or any other third-party NINJAM
client.

## Pull requests

- One logical change per pull request, with tests.
- CI must be green.
