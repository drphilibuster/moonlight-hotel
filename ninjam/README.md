# ninjam/

The hotel's fork of NINJAM.

`upstream/` is [justinfrankel/ninjam](https://github.com/justinfrankel/ninjam)
imported as a git subtree with its history, at upstream commit `f4c0eff`
(2025-06-01). The hotel modifies files in place; every modified upstream file
keeps its original notice and gains a "Modified by Moon Technologies LLC" line
under it.

Pull upstream changes with:

    git subtree pull --prefix=ninjam/upstream https://github.com/justinfrankel/ninjam.git master

## What was removed from the upstream tree

The hotel's own clients are the only way into a hotel room, so upstream's
clients aren't carried here:

| Removed | What it was |
| --- | --- |
| `jmde/` | ReaNINJAM, the REAPER extension client |
| `ninjam/{cmdclient--old,cocoaclient,cursesclient,guiclient,winclient}` | Cockos's standalone clients |
| `ninjam/ninjamcast` | A broadcasting client |
| `ninjam/{njasiodrv,ks}` | Windows ASIO and kernel-streaming audio for those clients |
| `ninjam/{audioconfig.cpp,audiostream*.{h,cpp},chanmix.*,njmisc.*,ninjam.dsw}` | Client-only audio I/O, mixer UI and utilities (including the Jesusonic effect interface) |

Nothing the hotel builds referenced them. If a future `subtree pull` brings
changes to a removed file, resolve the conflict by keeping it deleted.

## What the hotel builds from here

- **ninjamsrv** — from `upstream/ninjam/server` (the hotel server, M1).
- **njclient core** — `upstream/ninjam/{njclient,mpb,netmsg}` plus the WDL
  pieces they use (shared by the plugin, the Moonlight app, mixbot and
  moonlight-bot).

The licence audit (`tools/licence-audit`) defines those link sets and checks
every file in them. Results: [docs/licensing/ninjam-audit.md](../docs/licensing/ninjam-audit.md).
