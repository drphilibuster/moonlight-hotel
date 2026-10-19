# The Moonlight Hotel — build plan

## Context

`docs/DESIGN.md` is the system design for The Moonlight Hotel (Moon Technologies LLC, AGPLv3): interval-synced jamming from any DAW on NINJAM, with VJs, directors, live streaming, festival scheduling and media retention. It is deployed to AWS first with Terraform, then to self-hosted, GCP and Azure. No code exists yet. The only file is `moonlight-hotel/docs/DESIGN.md`. This plan covers the whole system, every milestone at the same depth. Milestones follow dependency order, not releases. Nothing here is a stand-in, a stub or a "for now".

Inputs checked during planning:
- NINJAM headers sampled: `ninjam/njclient.cpp` and `ninjam/server/usercon.cpp` (justinfrankel/ninjam, master) are both **GPL v2 or (at your option) any later version**. That is the expected result, but the full audit is still the first task.
- MoonVerb pins JUCE `9.0.3` (`../MoonVerb/CMakeLists.txt:17`). It builds VST3, AU and Standalone, and its CI (`../MoonVerb/.github/workflows/build.yml`) runs pluginval at strictness 10 and auval, then packages a pkg, an Inno Setup installer and a deb. The plugin CI reuses that pattern.
- Syphon publisher: `MoonTechnologies/src/Transmittal/{Publisher.hpp,Syphon.mm}`. It is IOSurface-based but tied to Rack's GL context. Its copyright is **James Frontz (Taxxess), GPL-3.0-or-later**, not the LLC.

Your four decisions, now part of the design:
1. **A native Moonlight app replaces the browser tab for players and absorbs the companion.** It holds the device identity and runs screen share and talkback with interval-stamped clocks, the clock outputs, the video bridges, the virtual audio output and the lossless uploader. The plugin pairs with it.
2. **Device sign-in replaces pasted config strings.** The app signs in through the lobby with the OAuth device grant and fetches room keys bound to the device key.
3. **NDI lives in a separate helper process**: Moon-only code, AGPLv3 plus an NDI linking exception.
4. **Rooms run in multiple regions.** The control plane has one home region (us-east-1). Room capacity is a per-region Terraform module.

---

## Part A — Flags: ambiguities and disagreements (each with the final design adopted below)

### Licensing
- **A1. NINJAM.** The sampled headers are v2-or-later. That lets us take GPLv3, and GPLv3 §13 permits combination with AGPLv3. The audit still has to classify every file, including vendored WDL (zlib-style), jnetlib, libogg and libvorbis (BSD). If any file turns out to be GPLv2-only, the hotel rewrites that file. There is no "clean-room client" branch: the client is the hotel's own code either way.
- **A2. The CLA's dual-licence rationale is partly hollow.** The LLC can never relicense Cockos's GPL code, JUCE's AGPL or Link's GPL. Dual licensing is only possible for components with no third-party copyleft: front desk, lobby, delayline, housekeeper, doorman, switcher and works. Keep the CLA, but state this in `CONTRIBUTING.md`.
- **A3. The Transmittal Syphon code is personally owned under GPL-3.0+.** Before it enters the monorepo, James licenses or assigns it to the LLC under the same CLA every contributor signs (recorded in `docs/licensing/`).
- **A4. The licence table is incomplete or wrong.** It says "JUCE 8", but the pin is 9.0.3: verify JUCE 9's licence (expected AGPLv3/commercial). It omits libogg, libvorbis, FLAC, Opus, mbedTLS (Apache-2.0, which is fine with v3 and *not* with v2-only, another reason the audit matters), LiveKit SDKs (Apache-2.0), FFmpeg (built without `--enable-nonfree`, native AAC encoder only), x264 (GPLv2+), pion (MIT), Syphon and Spout (BSD-2), Redis (choose **Valkey, BSD-3**) and libebur128 (MIT). Also verify: the AAX SDK's licence terms for an AGPL plugin, and whether JUCE 9 ships native CLAP (if so, use it instead of clap-juce-extensions).
- **A5. NDI** goes in a helper process (decision 3).

### "No SaaS" conflicts
- **A6. AcoustID's web API is a third-party SaaS, and its free tier is non-commercial.** Final design: self-host `acoustid-index` and the AcoustID server code, importing AcoustID's published data dumps on a schedule. Verify the code and data licences in M0.
- **A7. External services that cannot be self-built**, each behind an interface and listed in `docs/external-services.md`: Stripe (payments), YouTube and Twitch APIs (destinations, not components), Let's Encrypt (ACME CA), and the signing authorities (Apple notarization, Microsoft driver attestation, Avid/PACE).

### Architecture corrections
- **A8. There is no server-side interval clock in NINJAM.** Each client's interval phase is local, and upload indices aren't global, so "interval-boundary events from ninjamsrv" and `<interval>.flac` sorting don't exist upstream. Final design: the **hotel protocol** extension (M1).
  - The server owns an interval epoch and a global interval index, with NTP-style timesync.
  - Each client reports its phase offset `o_p` against the epoch.
  - Every upload carries its global index.
- **A9. One clock, used everywhere.** delayline delays each feed by a computed amount, not "exactly one interval". The broadcast runs on a **presentation clock** (PC):
  - A frame from player p captured at server time `t` is released at `t + T − o_p + D`.
  - `T = 60·BPI/BPM` (+T again in lossless mode).
  - `D` is a fixed per-show slack, at least the VJ round trip (default 500 ms).
  - The program mix and talkback are delayed by `D` too.
  - VJ frames are stamped with the PC time the VJ was hearing, so they need no interval delay.

  Without this, VJ visuals land an interval late, and talkback mixed into the stream is out of sync with the delayed music.
- **A10. The room task can't grow egress later**: ECS task definitions and Fargate sizes are immutable. Final design: the **room task** (always on) plus a separate on-demand **stage task** (Egress, 4 vCPU / 8 GB) that joins the room's LiveKit and Valkey over private IPs. This matches the cost table, which already prices egress separately.
- **A11. Every broadcast goes through a relay.** A non-festival show is a one-set ballroom. MediaMTX cannot switch inputs seamlessly or push out on its own, so the relay task gains a hotel-built **switcher**, which re-encodes once to a continuous output (correcting the $0.05/h figure), and a **packager** that writes HLS to S3. "Cut to lounge" ships with Picture (M3), so the **relay, switcher and lounge renderer move into M3**. M5 keeps scheduling, the hotel player, chat, tickets, libraries and retention. The lounge plays whatever the libraries hold; empty libraries mean generated visuals over changeover tracks. That is final behaviour, not a stand-in.
- **A12. As-aired program recording comes from the relay**, per show. Per-set programs are cut from it at the switch times, so room egress records only track composites (clean VJ set, per-player screens). Vault layout gains `shows/<show-id>/{program.mp4,hls/}`.
- **A13. Port 443 for everything.** NINJAM is plaintext TCP on 2049, and LiveKit can't put signalling and TURN/TLS on one 443. Each room gets a hotel-built **doorman** container that routes by SNI and ALPN on :443:
  - `<room>.rooms…` with ALPN `h2`/`http/1.1` goes to LiveKit signalling (TLS terminated by doorman).
  - `<room>.rooms…` with ALPN `moonlight-ninjam` goes to ninjamsrv over loopback (TLS terminated by doorman).
  - `<room>-turn.rooms…` is passed through to LiveKit TURN/TLS.

  The doorman also applies the IP ban set at L4. One-label names keep the `*.rooms` wildcard valid.
- **A14. Tempo goes through a control socket, not a "privileged system user".** ninjamsrv exposes a Unix-socket control API inside the task; every NINJAM-protocol privilege (`PRIV_BPM`, `PRIV_KICK`, votes) is disabled. The housekeeper applies tempo through that socket. The rule (tempo from the lobby only) is unchanged, and there is no privileged network identity to steal.
- **A15. Housekeeper teardown needs no IAM.** It is the essential container: it flushes and exits 0, so ECS stops the task. A checkout state machine reacts to the STOPPED event. A reaper catches tasks that die uncleanly.
- **A16. Rooms get no standing S3 or DNS permissions** (an ECS task role can't be scoped per room). The front desk mints per-room STS credentials by AssumeRole with a session policy limited to `rooms/<id>/…`, valid for one hour and refreshed by the housekeeper.
- **A17. Presigned PUTs can't be "valid for the room's life".** Their expiry is bounded by the signer's session, there is one per key, and uploads must outlive the room. Final design: an **upload grant**, per user per room, valid 30 days after checkout. The app trades it for batches of presigned PUTs carrying `x-amz-checksum-sha256`. The response lists the required headers per URL, which Azure SAS needs later.
- **A18. Interval chunks can't tier down economically.** That is ~4,500 objects per show-hour, and Glacier transition requests cost about a year of the storage saved. Final design: after checkout reconciliation, a works job **consolidates** stems into one FLAC per channel, with interval offsets recorded in the manifest. Export then needs no pre-rendering, and tiering moves a few large objects.
- **A19. Seven adapters aren't enough.** Final set:
  - Object store (with abstract tiers and restore; the S3 API alone can't serve Azure)
  - **Task launcher** (rooms, stage, relay, lounge, works)
  - Scheduler
  - Email
  - DNS
  - Secrets
  - Edge blocklist
  - **Realtime push** (API Gateway WebSocket on AWS; native WS plus Postgres LISTEN/NOTIFY elsewhere)
  - **Media delivery signer** (CloudFront signed cookies; Cloud CDN signed cookies; Azure is noted in P4)

  Payments is a provider interface, not a cloud adapter.
- **A20. Audience chat at scale shouldn't fan out through API Gateway `@connections`**: 3,000 viewers means 3,000 HTTP posts per message. Final design: during a public show, the relay task runs the **front desk image in `chathub` mode** (same code, same auth and moderation, Postgres-persisted). Room control and lobby state use the realtime adapter.
- **A21. The cost model is optimistic.**
  - Idle: a Lambda in a VPC needs egress for SES, Step Functions, Scheduler, STS and the API Gateway management API. Private DNS on an `execute-api` interface endpoint breaks calls to *public* APIs, so use one NAT gateway plus a free S3 gateway endpoint. Real idle is about **$60–65 a month** (NAT about $37 with its IP, WAF $8, Secrets $3, KMS $2, Route 53 $1.50, logs $5, Aurora storage $1, ECR about $2 per region).
  - Jam rooms: data out dominates. Five players watching four screens is about 8 Mbps out at tiled 360p (~$0.32/h) and about 30 Mbps at 720p (~$1.20/h).
  - Corrected table in M5.
- **A22. Payment-layer ban:** a card fingerprint is known only after card entry. Use Stripe Checkout with `capture_method=manual`. The webhook checks the fingerprint, then captures or cancels.
- **A23. Role model gaps.** Site roles (owner, admin, moderator) are missing from "five roles". Listener accounts (chat) need only a handle and accepted terms, not a full artist profile. Invite step 3, "picks a username", contradicts handles and is replaced by "completes artist profile".
- **A24. Terms acceptance has to exist in M1**, because room keys require it. The legal text still needs review before the first public show (M3). Moderation tools ship in M3.
- **A25. The design omits LiveKit Ingress**, which OBS WHIP needs. It goes in the room task (WHIP with transcoding bypassed). App users publish natively.
- **A26. The virtual audio device is a driver.**
  - macOS: AudioServerPlugIn (user space).
  - Windows: a KMDF virtual audio driver written fresh (the MS-PL sysvad sample is GPL-incompatible). It needs an EV certificate and Microsoft attestation signing.
  - Linux: a PipeWire node from the app.
- **A27. Device bans are spoofable**, because the client is AGPL and anyone can mint a fresh key. They stop casual evasion only, and the policy text should say so. Likewise, "the hotel's own clients are the only way in" is enforced by room keys and the hotel handshake, not by client authenticity.
- **A28. Self-hosted and other clouds:**
  - Self-hosted: MinIO's community edition went source-only/maintenance in late 2025 (verify), so propose **Garage (AGPLv3)**. Replace HashiCorp Vault (BUSL) with **OpenBao (MPL-2.0)**.
  - GCP: Cloud Run *jobs* accept no inbound traffic or UDP, so GCP rooms run on **GCE Container-Optimized OS instances**. Cloud Scheduler is cron-only, so one-shot opens use **Cloud Tasks**.
  - Azure: Blob storage isn't S3-compatible, so it gets a native adapter. Front Door has no signed cookies (see P4).
  - "Terraform for a single VM" needs a provider. Proposed: provider-free cloud-init plus a compose bundle; **decide before P2**.
- **A29. Vault versioning:** the night porter's in-place copies create noncurrent versions. Add a rule that expires noncurrent versions after 7 days.
- **A30. Smaller ambiguities**, settled as stated:
  - "A withdrawal deletes both copies" is read as master plus renditions.
  - "Unverified sessions" means a chosen visit counts only after 30 s of real playback from a non-flagged session.
  - Unpublished program and track recordings follow the audio clock and are never auto-deleted; the host and each contributor can delete their own.
  - Account deletion keeps frozen credits but unlinks the profile.
  - The idle thresholds are DB settings, not constants.
  - Closed open questions: Postgres stays (no DynamoDB); masters use Standard-IA.
- **A31. Repository layout amendment.** The design's layout has no home for ninjamsrv, the shared NINJAM core, the relay, batch jobs or drivers. Final layout:

```
ninjam/      upstream NINJAM as git subtree + hotel fork: core/ (njclient, mpb, netmsg, hotel protocol), server/ (ninjamsrv)
plugin/      JUCE plugin, all formats, on ninjam/core
app/         Moonlight app (was companion/): account, device, rooms, standalone engine, screen/talkback, uploader, clock, bridges
  ndi-helper/  separate process, AGPLv3 + NDI exception
drivers/     macos-hal/, windows-kmdf/
room/        housekeeper, doorman, mixbot, delayline, egress-template/, task definitions
relay/       switcher, packager, MediaMTX config
lounge/      lounge page (butterchurn or projectM per M3 measurement) + playlist logic
works/       batch jobs: consolidation, export, mixdown, fingerprint, renditions, image processing
frontdesk/   control plane, adapters, night porter, chathub mode
lobby/       web app
tools/       moonlight-bot (headless hotel client), syncscope (A/V offset analyser), loadgen
infra/       modules/{core,aws,selfhosted,gcp,azure}, live/{staging,prod}
docs/
```

### Languages and stacks (recommendation, not a question)
- **C++17 / JUCE 9.0.3**: plugin, app, mixbot and ninjam. **mbedTLS** for TLS in clients; servers sit behind doorman.
- **LiveKit native SDK** for the app and mixbot. Use LiveKit's C++ SDK if the M3 investigation shows it production-grade, otherwise the Rust core over its C FFI. The binding layer is hotel code either way.
- **Go**: front desk, housekeeper, doorman, delayline (pion + `server-sdk-go`), switcher (ffmpeg libs via cgo), packager and works orchestration.
  - Libraries: chi, pgx, sqlc, goose, go-webauthn, aws-sdk-go-v2, stripe-go.
  - The front desk runs as one binary, behind Lambda Web Adapter on AWS.
- **TypeScript**: SvelteKit (adapter-static) lobby, `@simplewebauthn/browser`, LiveKit JS, hls.js. The egress template and lounge page are TypeScript too.

---

## Part B — Cross-cutting design (fixed in M1, used by every milestone)

### Hotel protocol (NINJAM framing plus extensions; hotel clients only)
- Transport: TLS 1.3 on :443 through doorman, ALPN `moonlight-ninjam`. Legacy NINJAM auth is rejected.
- **Auth.** The server sends `AUTH_CHALLENGE` with hotel capability bits. The client replies `HOTEL_AUTH`, carrying:
  - the room key token: an Ed25519 JWS issued by the front desk with claims `room_id, user_id, key_id, handle, role, device_pk, terms_v, rights_at, exp`;
  - the device public key;
  - `sig_device(challenge‖key_id‖server_name)`.

  The server verifies the token against the front-desk key it received at bootstrap, then the device signature, then calls `admit()` through the housekeeper (ban layers: account, device, IP; key revocation). The NINJAM username is the handle.
- **Timesync.** `TS_PING{t1}` / `TS_PONG{t1,t2,t3}`, every 2 s. The client keeps a min-RTT-filtered offset.
- **Interval epoch.** `EPOCH{segment_start_server_ns, start_index, bpm, bpi, allowed_ratios[]}` is sent on change and at join. A tempo change starts a new segment at the next boundary.
- **Phase report.** `PHASE{o_p_ns, source: free|daw|link}` is sent on change.
- **Uploads** carry `global_index`. The server rejects indices outside a window of ±2.
- Message IDs come from a hotel range negotiated by capability, so upstream message types stay untouched. The spec lives at `docs/protocol/hotel-protocol.md`, with golden byte vectors.

### ninjamsrv control socket (`/run/room/ninjam.sock`, length-prefixed protobuf)
`SetTempo{bpm,bpi,ratios}→{effective_index}` · `Kick{user,reason}` · `RevokeKey{key_id}` · `SetLimits{max_players=5}` · `ListUsers` · `Subscribe→stream{IntervalBoundary{index,start_ns,bpm,bpi}, Join, Leave, UploadBegin{user,ch,index}, AdmitRequest}` · `AdmitReply{req_id,allow,reason}`.
mixbot connects as a system listener over loopback with a bootstrap-generated system token. It doesn't count toward the 5 players and can't upload.

### Front desk shape
One Go image with these modes:
- `serve`: HTTP API on Lambda Web Adapter.
- `events`: Lambda Web Adapter pass-through for API Gateway WebSocket, Step Functions, EventBridge and S3 events.
- `job:<name>`: night porter, cert renewer, reaper and reconciliation.
- `chathub`: in the relay task.

Adapters live in `frontdesk/adapters/<iface>/<provider>`. Each adapter has a **contract test suite** that every provider implementation must pass against the real service.

### Identity and tokens
- **Lobby sessions**: `__Host-` cookies (HttpOnly, Secure, SameSite=Lax), stored server-side, with CSRF double-submit for state-changing calls.
- **Magic link**: single-use, 15 min, bound to the requesting browser by a nonce cookie. A GET renders a confirm button and a POST consumes the link, which defeats mail-scanner prefetch.
- **Passkeys**: WebAuthn, resident keys, offered after first sign-in. A credential ID can't be registered to a second account.
- **App**: OAuth 2.0 device authorization grant (RFC 8628), approved at `moonlighthotel.com/activate` with a passkey or magic link. Access tokens are bound to the device Ed25519 key with DPoP-style proofs (RFC 9449 semantics, EdDSA). Refresh tokens rotate.
- **Plugin ↔ app pairing**: loopback TCP with a 6-digit code confirmed in the app. A Noise-XX-style handshake gives a stored pairing key. The plugin never holds account tokens or the device private key. The app signs handshake challenges for it.
- **Room service token**: RunTask overrides carry a one-time bootstrap token. The housekeeper exchanges it once for a room JWT (room_id, region, 1 h, refreshable), so later DescribeTasks exposure is harmless.

### Bans (enforced at sign-in, invite redemption, key issue, ninjamsrv admit, LiveKit token issue, chat)
- Layers are stored in `ban_layers(layer, value, prefix_len, expires_at)`.
- Email matching uses a normalized address: lowercase, plus-tags stripped, dots stripped for gmail/googlemail.
- IPv4 bans are /32 (or a stated prefix). IPv6 bans are /64. They default to 90 days.
- A match on the account, email, passkey, device or payment layer refuses. An IP-only match goes to `ban_reviews`.
- Propagation:
  1. revoke sessions and tokens in Postgres;
  2. push `ban.delta` to every live room over realtime; the housekeeper caches it and calls `Kick` and LiveKit `RemoveParticipant`;
  3. update the WAF IP set (and the doorman set through room push).
- Disposable-domain list: vendored, CC0, refreshed by CI.

### Multi-region rooms
- The home region (us-east-1) holds CloudFront, WAF, Aurora, the front desk, the vault and the relay default.
- Room regions are a list variable, for example `["us-east-1","eu-west-2","ap-southeast-2"]`. Each gets `aws/room-region`: a dual-stack VPC with public subnets only (no NAT), an ECS cluster, task definitions, ECR replicas, security groups, and a launcher plus checkout state machine.
- The host picks a region. The lobby suggests one by RTT to each region's configured probe URL.

---

## M0 — Repository and licence audit

**Order:** repository initialization first (your constraint), then the licence audit (the first engineering task). Nothing else starts until the audit is merged.

### Components and final interfaces
- `drphilibuster/moonlight-hotel`, created after you confirm, since it's public. It contains:
  - `LICENSE` (AGPLv3 text) and `COPYRIGHT` (Moon Technologies LLC).
  - `NOTICE` with the third-party licence inventory.
  - `CONTRIBUTING.md`, with the CLA and its scope per A2.
  - `CLA.md` (individual and entity). Signatures are collected by `contributor-assistant/github-action` (Apache-2.0) into a `cla-signatures` branch, so no SaaS is involved.
  - `README.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`.
  - `.github/` templates and CODEOWNERS.
- **AGPL §13 source offer**: every network-facing component reports its build commit. The front desk serves `GET /source`, the lobby footer links to it, and the app shows an About panel. Built in M0 as part of the release tooling (`tools/buildinfo`).
- **CI skeleton** (GitHub Actions):
  - lint for every language: clang-format, golangci-lint, eslint/prettier, terraform fmt/validate, tflint, checkov;
  - licence-header check (SPDX `AGPL-3.0-or-later` on every hotel file, with upstream headers preserved);
  - REUSE compliance;
  - a dependency licence gate: an allowlist that fails on unknown or incompatible licences;
  - CodeQL;
  - secret scanning.
- `ninjam/` imported as a **git subtree** at a pinned upstream commit, with history preserved. Hotel changes go on top. Each modified upstream file gets the GPL §2a / GPLv3 §5a "modified by Moon Technologies LLC" notice.
- **Licence audit** (`tools/licence-audit`, kept in CI): scans every file in `ninjam/` and in each vendored or fetched dependency, classifies its SPDX expression, and fails on any GPL-2.0-only file linked into an AGPL binary. The report goes in `docs/licensing/ninjam-audit.md`. It also covers WDL, jnetlib, Vorbis, Ogg and FLAC; the JUCE 9 licence; the AAX SDK terms; JUCE 9 native CLAP; the AcoustID code and data; the NDI SDK terms for the helper; and the Transmittal relicence (A3).
- `docs/external-services.md` (A7) and `docs/prerequisites.md`, which lists business blockers and the milestone each one gates:
  - Apple Developer *organization* enrollment (needs a D-U-N-S number): M2
  - EV code-signing certificate and Microsoft Partner Center: M2 (app), M4 (driver)
  - Avid developer agreement and PACE/iLok: M2
  - SES production access: M1
  - Google OAuth verification and a YouTube quota increase, plus a Twitch app: M3
  - Stripe, which waits on the EIN: M5
  - Legal review of the terms, the privacy policy and the library licence: M3, before the first public show
  - Registrar NS delegation for moonlighthotel.com: M1

### Terraform
- `infra/bootstrap/` (applied once, by hand, from the management account):
  - AWS Organizations with accounts `management`, `hotel-prod`, `hotel-staging` and `log-archive`.
  - SCPs: deny regions outside the configured list (excluding global services); deny leaving the org; deny disabling CloudTrail, Config or GuardDuty; deny root actions.
  - An org CloudTrail to `log-archive`.
  - A state bucket per account: S3 with versioning, SSE-KMS and **native S3 locking** (`use_lockfile`, Terraform ≥ 1.10; no DynamoDB).
  - GitHub OIDC provider and roles per account:
    - `ci-plan`: read-only, trusted for `pull_request`.
    - `ci-apply`: trusted only for `repo:drphilibuster/moonlight-hotel:environment:{staging,prod}`. It has a **permission boundary**, so any role it creates must carry the `hotel-boundary` policy, which prevents privilege escalation.
- `infra/modules/core`: provider-agnostic contract only.
  - Variables: `domain`, `home_region`, `room_regions`, room and stage sizing, `room_idle_minutes`, `max_room_hours`, retention thresholds, feature flags.
  - Outputs: the **adapter config document** (JSON) rendered into front-desk configuration, plus naming and tagging conventions.
  - Shared validation, for example `room_regions` must contain `home_region`.

### API and data model
- `GET /source` → `{repo, commit, built_at, licence}`.
- No database yet.

### State machines
- None.

### Security boundaries
- Branch protection: required reviews, signed commits, required checks.
- CI never holds long-lived cloud credentials (OIDC only).
- The prod apply environment requires manual approval.

### Tests
- Licence audit (CI, blocking).
- REUSE lint.
- An SCP test: the staging `ci-apply` role tries a denied region and expects AccessDenied.
- Bootstrap teardown runbook: `docs/runbooks/bootstrap.md`.

### Cost and teardown
- Under $1 a month: state buckets plus CloudTrail data. Accounts close through Organizations as documented.

### Definition of done
- The repo exists with the licence files, the CLA bot works on a test PR from a second account, and CI is green.
- The audit report is merged and shows **no GPLv2-only file in any AGPL-linked target**, or the rewrites are listed as M1 work items.
- Every A4/A6 verification item has a recorded answer.
- The Transmittal relicence is recorded.

---

## M1 — Foundations (design gate: "rooms run")

### Components and final interfaces
- **`ninjam/core`**: the hotel-forked njclient, mpb and netmsg, plus the hotel protocol client.
  - API (C++): `Engine::connect(RoomEndpoint, KeySigner&)`, `setLocalChannels`, `processBlock(in, out, n, HostTime)`, `onIntervalBoundary(cb)`, `phase()`, `timesync()`.
  - Audio-thread-safe (lock-free queues), with a pluggable `KeySigner` (the app signs; the bot uses a file-backed key).
  - Used by the plugin, the app's standalone engine, mixbot and moonlight-bot.
- **`ninjam/server` → ninjamsrv**:
  - Hotel auth replaces the user list; legacy auth and network privileges are removed.
  - Interval epoch, timesync, phase tracking, global indices, the control socket and the 5-player limit.
  - Chat is kept, with server-side length and rate limits.
- **`tools/moonlight-bot`**: a headless hotel client on `ninjam/core` that plays deterministic test signals. Each interval carries an index-encoded tone burst plus a click track. It verifies received intervals. It is a real hotel client and the only test client at every milestone.
- **`room/doorman`** (Go): SNI/ALPN router on :443, the TLS terminator for signalling and ninjam, TURN passthrough, and the L4 IP deny set (pushed by the housekeeper), with per-IP connection rate limits.
- **`room/housekeeper`** (Go, essential container):
  - bootstrap exchange;
  - realtime connection to the front desk;
  - the admit proxy with a ban-delta cache;
  - `SetTempo` application;
  - heartbeats (players, levels summary, task health);
  - idle FSM;
  - manifest maintenance (S3 snapshot through scoped credentials on each tempo change and every 60 s, final flush at exit);
  - the in-task readiness gate (ninjamsrv, doorman, later livekit).
- **Room task definition** (M1 containers): `doorman`, `ninjamsrv`, `housekeeper`, plus `mixbot` in listener mode for archive and timing verification, without LiveKit until M3.
  - ARM64. 1 vCPU / 2 GB in M1; final 2 vCPU / 4 GB from M3, recorded in core variables.
  - Shared bind volume `/run/room`.
- **Front desk (`frontdesk/`)**: accounts, profiles, terms, rooms, invites, keys, bans, admin, the launcher callback and the realtime handlers. Adapters implemented for AWS: Object store, Task launcher, Scheduler (used in M1 by the reaper, cert renewal and room scheduled-close), Email, DNS, Secrets, Edge blocklist and Realtime.
- **Cert renewer** (`job:certs`): ACME DNS-01 via the DNS adapter, using lego as a library (MIT). It covers `*.rooms.<domain>` and stores the cert in Secrets.
  - Runs daily and renews at 30 days left; uses Let's Encrypt's 6-day short-lived profile if the measurement favours it.
  - Rooms read the cert when they start.
- **Lobby (M1 surfaces)**:
  - sign-in (magic link, passkey);
  - artist profile editor, with completeness enforced and image upload;
  - public `/@handle` page;
  - terms acceptance;
  - room creation (region, BPM, BPI, ratios, invitees, roles);
  - invite redemption;
  - room page (open/close, tempo control, members, status over realtime);
  - "Waking the hotel" during Aurora resume;
  - `/activate` (device grant);
  - admin: bans, reviews, audit.

### Terraform
- `modules/core`: as in M0, plus room sizing and idle variables.
- `modules/aws/` submodules:
  - **`network-home`**: dual-stack VPC with a /56. Three AZs, each with public and private subnets. One NAT gateway plus EIP, an egress-only IGW and an S3 gateway endpoint. Flow logs to log-archive.
  - **`dns`**: zone `moonlighthotel.com`. Delegated zone `rooms.moonlighthotel.com`, kept separate so IAM can scope room record writes to it. DNSSEC signing with a KMS asymmetric key in us-east-1. CAA record limited to letsencrypt.org and amazon.com.
  - **`edge`**:
    - ACM cert (us-east-1).
    - S3 lobby bucket, private behind OAC.
    - CloudFront distribution: `/` to the lobby, `/api/*` and `/source` to an API Gateway **HTTP API** origin. The origin is guarded by a rotating `X-Origin-Verify` secret header that the front desk checks; HTTP APIs can't carry WAF or resource policies.
    - WAFv2 web ACL: AWS managed core rules, rate-based rules, and the **ban IP sets** (v4 and v6) referenced by a block rule.
    - Response headers policy: CSP, HSTS preload, COOP/COEP where compatible.
  - **`data`**: Aurora PostgreSQL 16 Serverless v2, min **0 ACU** (auto-pause), max 4. Private subnets. IAM DB auth on. KMS CMK. Backups for 14 days, deletion protection, Performance Insights off. Parameter group with `rds.force_ssl=1`.
  - **`frontdesk`**:
    - ECR repo (immutable tags, scan on push, lifecycle).
    - Lambda functions from one image: `api` (Lambda Web Adapter, 1024 MB, arm64, VPC private subnets, reserved concurrency 50 to cap DB connections), `events` and `jobs`.
    - HTTP API with Lambda proxy integration.
    - **WebSocket API** at `rt.<domain>` with `$connect`, `$disconnect` and `$default` routed to `events`, and a custom domain.
    - Log groups with 30-day retention.
  - **`email`**: SES domain identity, Easy DKIM, a custom MAIL FROM, DMARC record, configuration set with a bounce/complaint SNS topic routed to `events` (suppression), and an IAM condition `ses:FromAddress`.
  - **`secrets`**: KMS CMKs (`hotel-data`, `hotel-secrets`). Secrets for the room wildcard cert, the front-desk Ed25519 signing keys (kid-rotated), the origin-verify header, the DPoP nonce key and the CloudFront key-group private key (M5).
  - **`vault`**: bucket `vault-<acct>` with versioning, SSE-KMS (bucket key on), Block Public Access, Object Ownership enforced, TLS-only policy and EventBridge notifications. Lifecycle: noncurrent versions expire after 7 days; aborted multipart uploads after 1 day. `prevent_destroy` in prod.
  - **`room-region`** (one per region, provider alias):
    - Dual-stack VPC with public subnets only.
    - Security groups:
      - room SG: inbound TCP 443 and UDP 7882 (WebRTC mux, from M3), from anywhere v4/v6. Valkey port 6379 open only from the stage SG.
      - stage SG: egress only.
    - ECS cluster with Container Insights off and the account-level `dualStackIPv6` setting.
    - Task definition family `room`: execution role, task role, Fargate platform 1.4, ARM64, `ephemeralStorage` 21 GB.
    - ECR replication rule from the home region.
    - **Launcher** and **checkout** Step Functions (Standard).
    - EventBridge rule: ECS Task State Change STOPPED for the room family starts checkout.
  - **`scheduler`**: EventBridge Scheduler group `hotel` and a scheduler-target role.
  - **`observability`**:
    - CloudWatch alarms: API 5xx, Lambda errors and throttles, launcher failures, room count, Aurora ACU at max, SES bounce rate.
    - An SNS topic to email.
    - Budgets: a monthly budget with forecast alerts.
- `infra/live/{staging,prod}`: root modules wiring core into aws with per-environment tfvars. Staging uses `force_destroy` on buckets and no deletion protection.

### API (M1)

**Auth**
- `POST /api/auth/magic-link`
- `GET|POST /api/auth/magic-link/confirm`
- `POST /api/auth/passkeys/{register,login}/{options,verify}`
- `DELETE /api/auth/passkeys/{id}`
- `GET /api/auth/sessions`
- `DELETE /api/auth/sessions/{id}`
- `POST /api/auth/logout`

**Device grant**
- `POST /api/oauth/device/authorize {install_id, device_pk, client}`
- `POST /api/oauth/device/approve {user_code}` (lobby session)
- `POST /api/oauth/token` (`device_code`, `refresh_token`; DPoP-bound)

**Profile**
- `GET|PUT /api/me/profile`
- `POST /api/me/profile/image` (presigned PUT → works job)
- `GET /api/artists/{handle}`
- `GET /api/handles/{h}/available`

**Terms**
- `GET /api/terms/current`
- `POST /api/terms/accept {version}`

**Rooms**
- `POST /api/rooms`
- `GET|PATCH /api/rooms/{id}`
- `POST /api/rooms/{id}/open`
- `POST /api/rooms/{id}/close`
- `PUT /api/rooms/{id}/tempo {bpm,bpi}`
- `PUT /api/rooms/{id}/ratios`
- `POST /api/rooms/{id}/invites`
- `DELETE /api/rooms/{id}/invites/{iid}`
- `POST /api/invites/{code}/redeem`
- `PUT /api/rooms/{id}/members/{uid}`
- `DELETE /api/rooms/{id}/members/{uid}`
- `GET /api/me/rooms`
- `POST /api/rooms/{id}/keys {rights_confirmed:true}` (app; DPoP; requires a complete profile, current terms, membership and no ban)

**Admin**
- `GET|POST /api/admin/bans`
- `DELETE /api/admin/bans/{id}`
- `GET /api/admin/ban-reviews`
- `POST /api/admin/ban-reviews/{id}`
- `GET /api/admin/audit`
- `POST /api/admin/users/{id}/suspend`

**Internal** (room JWT)
- `POST /internal/rooms/bootstrap`
- `POST /internal/rooms/{id}/admit`
- `POST /internal/rooms/{id}/events` (batch)
- `POST /internal/rooms/{id}/credentials` (STS, scoped)
- `POST /internal/rooms/{id}/ready`
- `POST /internal/rooms/{id}/exiting`

**Realtime WebSocket messages**
- Room channel: `tempo.set`, `room.close`, `ban.delta`, `key.revoke`, `member.remove`, `heartbeat`, `state`
- Lobby channel: `room.state`, `tempo.applied`, `members`

**Other**
- `GET /api/health`
- `GET /source`

### Data model (migrations `0001_*`)
- **Accounts and identity**
  - `accounts(id, status, created_at, deleted_at)`
  - `emails(account_id, address, normalized, verified_at, primary)` with a unique index on `normalized`
  - `magic_links(token_hash, email, nonce_hash, expires_at, used_at)`
  - `passkeys(credential_id PK, account_id, public_key, sign_count, transports, created_at)`
  - `sessions(id, account_id, kind web|app, device_id, created_at, last_seen_at, revoked_at)`
  - `devices(id install_id, account_id, public_key, platform, first_seen, last_seen, revoked_at)`
  - `device_grants(device_code_hash, user_code, install_id, device_pk, account_id, status, expires_at)`
  - `refresh_tokens(hash, session_id, device_id, rotated_from, expires_at, revoked_at)`
  - `sign_in_events(account_id, ip inet, ip_prefix cidr, device_id, ua, at)`, purged after 90 days unless the account is banned
- **Profiles**
  - `artist_profiles(account_id, artist_name, handle citext unique, roles text[], bio, location, image_key, pro_name, ipi, completed_at)`
  - `profile_links(account_id, kind, url)`
  - `handle_history(account_id, handle, from, to)`
- **Terms**
  - `terms_versions(version, published_at, text_key)`
  - `terms_acceptances(account_id, version, at, ip)`
- **Rooms**
  - `rooms(id, host_id, region, status, bpm, bpi, allowed_ratios int[][], idle_minutes, music_licence, created_at, opened_at, closed_at)`
  - `room_members(room_id, account_id, roles text[], status)`
  - `invites(id, room_id, email_normalized, roles, code_hash, status, expires_at, redeemed_by)`
  - `room_keys(key_id, room_id, account_id, device_id, role, rights_confirmed_at, terms_version, issued_at, expires_at, revoked_at)`
  - `room_tasks(room_id, task_arn, region, ipv4, ipv6, state, started_at, stopped_at, stop_reason)`
  - `room_tempo_events(room_id, requested_by, bpm, bpi, requested_at, effective_index, applied_at)`
  - `room_connections(room_id, connection_id, connected_at)`
  - `lobby_connections(connection_id, account_id, subscriptions)`
- **Bans and audit**
  - `bans(id, account_id, reason, created_by, created_at, expires_at, lifted_at)`
  - `ban_layers(ban_id, layer, value, prefix cidr, expires_at)`
  - `ban_reviews(id, candidate_account, matched_layer, evidence, status)`
  - `audit_log(id, actor, action, target, data jsonb, at)`, append-only (a trigger denies UPDATE and DELETE)
  - `disposable_domains(domain)`
- **Settings**
  - `settings(key, value jsonb)`

### State machines
- **Room**: `draft → launching → open ⇄ (tempo changes) → closing → checked_out`, and `launching → failed`. Only the launcher, checkout and front desk write `status`, guarded by `UPDATE … WHERE status=$expected`.
- **Launcher (Step Functions, per region)**:
  1. `Validate`
  2. `RunTask`: overrides carry `ROOM_ID`, the bootstrap token and region; `capacityProviderStrategy` FARGATE; propagate tags.
  3. `WaitForENI`: loop `DescribeTasks` every 5 s, up to 3 min.
  4. `DescribeNetworkInterfaces` for the public IPv4 and IPv6.
  5. `UpsertDNS`: A and AAAA records for `<room>` and `<room>-turn`, TTL 30.
  6. `WaitForReady`: `lambda:invoke.waitForTaskToken`. The front desk stores the token and calls `SendTaskSuccess` when the housekeeper posts `/ready`. Heartbeat timeout 180 s.
  7. `MarkOpen` and notify the lobby.

  On any failure: `StopTask` → `DeleteDNS` → `MarkFailed`.
- **Checkout (Step Functions)**, triggered by the STOPPED event or a close request: `StopTask` if still running → `DeleteDNS` → `RevokeKeys` → `VerifyManifestFlushed` (or reconstruct it from events) → `MarkCheckedOut` → enqueue post-room jobs (none in M1).
- **Housekeeper idle FSM**: `booting → ready → active ⇄ idle_countdown(N min, no players) → flushing → exit(0)`. `max_room_hours` and the front-desk `room.close` both lead to `flushing`.
- **Reaper** (`job:reaper`, every 10 min): rooms open with no heartbeat for 3 min, tasks with no DB row, DNS records with no room.
- **Account**: `pending_email → active (profile_incomplete | complete) → suspended | banned → deleted`.
- **Invite**: `issued → redeemed | expired | revoked`.
- **Room key**: `issued → bound (first admit fixes device_id) → revoked | expired`.
- **Tempo**: lobby `PUT` → validate (host only, ratios valid) → `tempo.set` to the housekeeper → `SetTempo` → `effective_index` acknowledged → stored and broadcast → manifest appended.
- **Ban**: `create → propagate (sessions, keys, rooms, WAF) → active → expired | lifted`. An IP-only evasion match goes to a review.

### Security boundaries (IAM)
- **`frontdesk-api` role**:
  - `rds-db:connect` to the `frontdesk` DB user.
  - `s3:PutObject` only on `rooms/*/uploads/profile/*` (M1).
  - `states:StartExecution` and `SendTask*` on the launcher and checkout machines in every room region.
  - `scheduler:CreateSchedule` and `DeleteSchedule` on group `hotel`, plus `iam:PassRole` limited to the scheduler-target role.
  - `ses:SendEmail` with the `ses:FromAddress` condition.
  - `execute-api:ManageConnections` on the WS API stage.
  - `wafv2:GetIPSet` and `UpdateIPSet` on the two ban sets.
  - `secretsmanager:GetSecretValue` on the named ARNs, plus `kms:Decrypt` through the secrets CMK.
  - `sts:AssumeRole` on `room-scoped-media`, with `sts:SourceIdentity` set to the room ID.
  - Boundary: `hotel-boundary`.
- **Launcher role**:
  - `ecs:RunTask` with conditions `ecs:cluster` and the task definition family.
  - `iam:PassRole` for exactly the room execution and task roles, with `iam:PassedToService=ecs-tasks`.
  - `ec2:DescribeNetworkInterfaces`.
  - `route53:ChangeResourceRecordSets` on the rooms zone, with `route53:ChangeResourceRecordSetsNormalizedRecordNames` matching `*.rooms.moonlighthotel.com` and record types A and AAAA only.
  - `lambda:InvokeFunction` on `events`.
- **Room execution role**: ECR pull and logs, plus `secretsmanager:GetSecretValue` on **only** the wildcard cert secret.
- **Room task role**: no permissions. ECS Exec (`ssmmessages`) only in staging.
- **`room-scoped-media` role**: trusted only by `frontdesk-api`, with a 1-hour maximum session. Its policy is the union of what any room may do: Put and Get on `rooms/*/manifest.json`, `rooms/*/show/*`, `rooms/*/video/*` and Get on `rooms/*/stems/*`. Each AssumeRole carries a **session policy** that narrows `*` to the one room ID.
- **Network**:
  - Rooms: inbound 443/tcp only in M1. ninjamsrv and the control socket are never exposed, because doorman is the only listener.
  - Aurora: reachable only from the Lambda SG.
  - The HTTP API is reachable only with the origin-verify header (the front desk rejects anything else).
- **Data**: SSE-KMS everywhere, TLS-only bucket policies, IAM DB auth (no DB passwords). PRO/IPI fields are encrypted at the column level with envelope encryption (KMS data key).
- **Wildcard key blast radius**: a compromised room can present any `*.rooms` name. MITM still needs network position. This is accepted and documented; the short-lived cert profile reduces it further.

### Tests
- **Unit** (Go, C++): hotel protocol codec against golden vectors; interval maths (epoch segments, global index at ratio changes); email normalization; ban matching (v6 /64); token signing and verification; DPoP proofs.
- **ninjamsrv**: protocol fuzzing (libFuzzer on every message parser); the auth matrix (bad signature, wrong device, expired key, revoked key, banned IP, sixth player).
- **Adapter contract tests** against real AWS in staging: object store presign, put, get and checksum; launcher launch, ready and stop; scheduler one-shot; SES to a test inbox (a mailbox on a domain the LLC controls, receiving through an SES receipt rule into S3); DNS upsert and delete; secrets; WAF IP set; WS push.
- **Integration**: front desk with real Postgres in CI (Postgres container, migrations up and down) via sqlc.
- **End to end** (staging, `tools/e2e`):
  - Sign-up through a magic link read from the test inbox. WebAuthn uses Chrome DevTools virtual authenticators in a Playwright-driven lobby.
  - Profile, then room creation in two regions, then five `moonlight-bot`s jam for 30 minutes.
  - The bots assert the global index sequence, timesync offset under 5 ms, and a tempo change applied at exactly `effective_index` for all.
  - Idle teardown happens within N+1 minutes.
  - **Zero residue**: no task, DNS record or key left after checkout.
  - Ban tests at every M1 entry point (sign-in, redemption, key issue, admit, WAF).
- **Load**: 20 concurrent room launches per region with a launch-time histogram (target p95 under 90 s, with SOCI indexes on images).

### Cost and teardown
- Idle is about $60–65 a month (A21). A room is about $0.04/h of compute plus tiny data, since there is no video yet.
- Staging `terraform destroy` is clean. Prod has deletion protection on Aurora and `prevent_destroy` on the vault and zones. The runbook documents final snapshots.

### Definition of done ("rooms run")
- A new person goes from email to passkey, profile and terms acceptance.
- A host creates a room in a chosen region, invites four people (redeemed through magic link), and opens it from the lobby.
- Five hotel clients (bots) connect over TLS on 443 through doorman and jam with global interval indices.
- A tempo change from the lobby applies at the next boundary for everyone.
- The room checks itself out after idle with zero residue, and every ban layer available in M1 refuses at every M1 entry point.
- All of the above passes from CI against staging, and `terraform plan` on prod shows no drift.

---

## M2 — Client (design gate: "friends jam")

**Investigation first: the lossless uploader** (`plugin/` capture and `app/` porter). Its code is the component itself. Questions it must answer with measurements, recorded in `docs/engineering/uploader.md`:
1. FLAC encode off the audio thread at 48 kHz/24-bit. What ring size survives a 500 ms GUI or disk stall at 32-sample buffers?
2. Plugin-to-app transfer under sandboxed hosts: Logic's out-of-process AU, AUv2 in Live, VST3 in Bitwig, AAX in Pro Tools. Does loopback TCP work, and what spools when the app is absent?
3. Resume semantics after a kill -9 in the DAW, the app or the OS, and after network loss for 1 hour.
4. Upload throughput and ordering at 5 channels × 8 s intervals over a 1 Mbps uplink.
5. The S3 checksum and grant-refresh path, including clock skew.

### Components and final interfaces
- **Moonlight plugin** (JUCE 9.0.3):
  - Formats: VST3, AU, AAX, CLAP (JUCE native or clap-juce-extensions per M0) and LV2 on Linux (JUCE-provided).
  - On `ninjam/core`. Up to 4 local channels.
  - Host sync: reads the transport and tempo; computes the valid p/q ratios from the room's BPI and the host's allowed list; flags drift; reports phase source `daw` when the transport is aligned.
  - Monitoring: Vorbis up and down (NINJAM).
  - Capture: each local channel's interval goes to FLAC through a lock-free SPSC ring, then to an encoder thread, then to the app over the paired link, or to a local spool if the app is unreachable.
  - Local session save: every participant's decoded intervals plus own FLAC, written to a session folder as `<user>/<channel>/<index>.{ogg,flac}` with a manifest.
  - UI: room list (from the app), key status, channels, levels, ratio picker and drift indicator, uploader status.
  - The plugin never talks to the front desk directly.
- **Moonlight app** (JUCE standalone application):
  - **Device identity**: an install ID plus an Ed25519 key in the macOS Keychain, Windows CNG/DPAPI or Linux Secret Service.
  - Device sign-in and DPoP.
  - Room browser: issues and receives room keys, and asks for the per-room rights confirmation.
  - Pairing service for plugins.
  - **Standalone engine**: the plugin engine hosted directly, with audio interface I/O, for players without a DAW.
  - **Porter (uploader)**: a durable SQLite queue (public-domain licence) in the app data directory. Upload grant → batch presign → PUT with `x-amz-checksum-sha256` and the headers the grant lists → confirm. Exponential backoff, resume across restarts, and grant renewal up to 30 days after checkout.
  - Auto-update: signed release feed, Ed25519-signed manifests and platform installers.
  - About and source (AGPL).
- **Release engineering**:
  - macOS: universal, signed with Developer ID and notarized. pkg containing the app, VST3, AU, AAX and CLAP.
  - Windows: signed with the EV certificate. Inno Setup (as MoonVerb), with AAX wrapped by PACE `wraptool`.
  - Linux: deb and tarball (VST3, CLAP, LV2, app).
  - Reproducible version stamping (`tools/buildinfo`).
- **Front desk additions**: upload grants and presign batches; S3 `ObjectCreated` events through EventBridge to `events`, which records stems and verifies checksums; archive opt-ins; manifest API; export jobs; release feed.
- **works (Fargate, via task launcher)**:
  - `consolidate`: after checkout plus a reconcile window, per room and channel, builds a concatenated FLAC with the interval offset table in the manifest. Silent or missing intervals are written as digital silence and marked in the manifest. The chunks are deleted after a verified consolidation.
  - `export`: zip (store mode) or per-channel concatenated FLAC with tempo-map metadata, streamed through S3 multipart.
  - `image`: profile images resized to 3 renditions and re-encoded, which strips all metadata including GPS.
- **Lobby additions**: archive settings per room and per player; stems listing and export page; manifest viewer (tempo map); downloads page; devices page (list and revoke).

### Terraform
- `modules/core`: release channel variables, grant TTL, reconcile window.
- `modules/aws`:
  - **`vault`**: EventBridge rule for `ObjectCreated` on `rooms/*/stems/*`, routed to `events`.
  - **`works`**: ECR repo; Fargate task definitions per job (Spot capacity provider in the home region); a works SG with egress only (through the S3 gateway endpoint and the NAT); `works-role` with S3 Get and Put on `rooms/*` and `exports/*` and Delete on `rooms/*/stems/*` chunk keys only.
  - **`releases`**: bucket `releases-<acct>` behind CloudFront path `/downloads/*` (OAC), immutable object keys.
  - **`frontdesk`**: env and config for grants. The `frontdesk-api` role gains `s3:PutObject` on `rooms/*/stems/*` (needed to sign the PUTs), `ecs:RunTask` for the works family (with PassRole), and `s3:GetObject` on `exports/*` for signed downloads.

### API (M2)
- `POST /api/rooms/{id}/archive {enabled}` (host)
- `PUT /api/rooms/{id}/members/me/archive {channels[]}` (player opt-in)
- `POST /api/upload-grants {room_id}` → `{grant_id, expires_at}` (app; requires a key)
- `POST /api/upload-grants/{gid}/urls {items:[{channel, index, sha256, size}]}` → `[{key, url, method, headers}]`
- `GET /api/upload-grants/{gid}/status` → missing indices
- `GET /api/rooms/{id}/manifest`
- `GET /api/rooms/{id}/stems`
- `POST /api/rooms/{id}/exports {format, channels, range}`
- `GET /api/exports/{eid}` → status and a signed URL
- `GET /api/releases/latest?platform&channel`
- `GET /api/me/devices`
- `DELETE /api/me/devices/{id}`

### Data model (`0002_*`)
- `archive_settings(room_id, enabled, set_by)`
- `archive_optins(room_id, account_id, channels int[], at)`
- `upload_grants(id, room_id, account_id, device_id, expires_at, revoked_at)`
- `stem_chunks(room_id, account_id, channel, global_index, key, size, sha256, uploaded_at, verified_at)`, with a unique index on `(room_id, account_id, channel, global_index)`
- `stem_consolidations(room_id, account_id, channel, key, size, sha256, index_from, index_to, gaps int[], at)`
- `manifests(room_id, version, key, at)`
- `exports(id, room_id, requested_by, spec jsonb, status, key, expires_at)`
- `releases(platform, channel, version, manifest_key, sig, published_at)`

### State machines
- **Chunk**: `captured → encoded → handed_to_app | spooled → queued → presigned → uploading → uploaded → verified`. Retries happen at every arrow. A chunk is `abandoned` only by user action after its grant expires.
- **Grant**: `active → renewing → active`, then `expired` 30 days after checkout, or `revoked` by a ban.
- **Pairing**: `unpaired → code_shown → confirmed → paired → revoked`.
- **Post-room** (appended to checkout): `reconcile_wait (24 h or every grant drained) → consolidate → verify → delete_chunks → done`. Late chunks after consolidation are appended in a second pass, so consolidation is idempotent and versioned.
- **Export**: `queued → running → ready → expired`.

### Security boundaries
- Presigned URLs are per key, expire in 15 minutes, are checksum-bound and size-limited (`content-length-range` enforced by the declared size).
- A grant is bound to the device key through DPoP. A ban revokes every grant.
- The plugin holds only its pairing key. The app holds the device key and account tokens.
- Works tasks run in the home region; the role can delete only stem chunk keys.
- Release feeds are signed with a separate Ed25519 release key that is offline in the prod Secrets account.

### Tests
- **Plugin**: pluginval strictness 10 for every format; `auval`; `clap-validator`; the AAX Validator; ASan and TSan builds of `ninjam/core`; and an **audio-thread allocation and lock detector** (a RealtimeSanitizer build).
- **DAW matrix** (manual plus scripted where the host allows): Live, Logic, Pro Tools, Bitwig, Cubase, Studio One, FL Studio, REAPER (as a host only; its bundled NINJAM client is never used) and Ardour, each on macOS, Windows and Linux as applicable.
- **Uploader chaos**: kill the DAW, app and OS mid-interval; 1 hour of packet loss; disk full; clock skew ±10 min. Assert eventual completeness and checksums.
- **End to end**: five bots play 1 hour with archiving on, two of them disconnected for 10 minutes. After checkout, every interval of every opted-in channel is present and verified, consolidated FLACs decode, and the zip export plus concatenated export reproduce the bot signals sample-exactly.
- **Local session save** round trip.

### Cost and teardown
- Stems are about 3 GB per show-hour in Standard (about $0.07/month) until M5 tiering. Works on Fargate Spot is pennies per job.
- Releases bucket: `prevent_destroy` in prod.

### Definition of done ("friends jam")
- Five real people on mixed OSes, in at least five different DAWs including Pro Tools (signed AAX) and a CLAP host, sign in through the app and jam for an hour.
- At least one player uses the standalone app without a DAW.
- The lossless archive is complete and verified, including through a forced disconnect.
- Stems export works, and each player's local session save opens.
- The installers are signed and notarized on all three OSes.
- The uploader investigation report is merged.

---

## M3 — Picture (design gate: "synced stream")

**Investigation first: mixbot**, then **delayline**. Their code is the components. Reports go in `docs/engineering/{mixbot,delayline}.md`.
- **mixbot**:
  1. Can LiveKit's native SDK publish server-side audio with steady pacing from a headless Linux container?
  2. What is the decode-and-mix cost for 5 players × 4 channels on 2 vCPU ARM?
  3. What is the lossless deadline-miss rate when FLAC chunks are fetched from S3 within one interval?
  4. How stable are levels-message timing and the PC alignment?
- **delayline**:
  1. Can pinned per-layer subscriptions (three subscribers per track) be republished as simulcast?
  2. Keyframe availability: forced periodic keyframes from the app publisher (2 s). Late subscribers wait at most 2 s.
  3. Map RTCP SR (NTP↔RTP) plus the app's **clock-map** data messages `(track, sender_wall_ns, server_offset_ns, interval_index, phase)` to the presentation clock.
  4. Buffer memory at 4 Mbps × (T + D) per layer, with T up to 32 s.
  5. Egress Chrome playout: is `jitterBufferTarget` equalised across every receiver?
  6. Measured A/V error with syncscope.

### Components and final interfaces
- **Room task, final** (2 vCPU / 4 GB ARM): `doorman`, `ninjamsrv`, `housekeeper`, `mixbot`, `livekit` (self-hosted server, UDP mux 7882, TURN/TLS behind doorman), `delayline`, `valkey` (in-memory, `requirepass` per room, bound to the task ENI for the stage task) and `ingress` (from M4).
- **mixbot**:
  - A NINJAM listener that decodes, then mixes with the **room mix state** (per-channel gain, pan, mute; set by the host or director through realtime, versioned and logged per interval in the manifest so that mixdown uses the true settings over time, not only the final ones).
  - Publishes `program-mix` (Opus 48 kHz stereo, 192 kb/s, FEC on, DTX off) and `levels` data messages per interval, ahead of the PC boundary.
  - Lossless mode: fetches FLAC with scoped credentials. On a deadline miss it uses that interval's Vorbis for that channel and records `degraded[]` in the manifest.
- **delayline**: subscribes to every screen, VJ, director and talkback track, plus `program-mix`. It republishes `pc/<orig-track>` tracks released on the presentation clock (A9), with tempo changes applied at boundary events from the control socket. Directors and egress subscribe only to `pc/*`; moderators and players see live tracks.
- **Moonlight app additions**:
  - Screen share: ScreenCaptureKit on macOS, Windows.Graphics.Capture on Windows, the PipeWire portal on Linux. Simulcast 1080p/720p/360p; default 720p at 15 fps for players; 2 s keyframes.
  - Talkback mic with a headphone check: it warns when the output device isn't headphones (best effort per platform) and blocks talkback publishing until confirmed.
  - Clock-map data messages.
  - Subscribes to other players' live screens.
- **Stage task** (on demand, 4 vCPU / 8 GB, room region): LiveKit Egress.
  - RoomComposite with the **hotel egress template** (`room/egress-template`) streaming SRT, or RTMPS if Egress lacks SRT (decided in the investigation), to the relay.
  - TrackComposite recordings: clean VJ set (`pc/program-mix` + VJ) and per-player screens, each when its person opted in, written to `rooms/<id>/video/` with scoped credentials.
- **Egress template**:
  - Layout FSM: featured, grid, PiP-over-VJ.
  - Hysteresis from `levels`. Cuts only at PC interval boundaries.
  - Director override lease.
  - Overlays: performer credits from frozen artist names; talkback mixed ducked under music when the host enables it.
  - Equalised receiver playout targets.
- **Relay task** (home region by default, or the ballroom's region; 2 vCPU / 4 GB):
  - MediaMTX (SRT/RTMP ingest per source path).
  - **switcher** (Go + libav*): a continuous re-encode to 1080p30 H.264 + AAC, keyframe every 2 s, CBR 6 Mb/s. Inputs are the active room, the lounge and slate-free black only during the first preroll second. Commands: `switch(source, at)`, `cutToLounge`, `return`, `kill(dest)`, `restore(dest)`.
  - Outputs: RTMPS to each destination, SRT to the packager.
  - **packager**: fMP4 HLS (2 s segments, ladder 1080/720/480/360 plus an audio-only rendition; the encode happens in the packager) written to `shows/<show>/hls/`, plus `program.mp4` as-aired (fragmented MP4, multipart upload), with a switch-time index used to cut per-set programs.
  - `chathub` (front desk image) for M5.
- **Lounge task** (2–4 vCPU; launched with a show, kept hot as the switcher's standby input):
  - Headless Chrome renders the lounge page and is encoded to SRT into the relay.
  - Picture: a past VJ set, or generated visuals. **butterchurn vs projectM is decided by measurement here**: frame time at 720p/1080p on Fargate CPU using SwiftShader WebGL vs projectM on llvmpipe. One is chosen and the other is never built.
  - Music in the design's priority order.
  - Overlays: now playing, countdown.
  - Its playlist API reads library state (empty until M5 pipelines publish).
- **Destinations**:
  - YouTube: OAuth (scopes `youtube.force-ssl`). Creates or binds a liveBroadcast and stream, sets `selfDeclaredMadeForKids=false` and age restriction, and writes the description with every performer's artist name and links.
  - Twitch: OAuth (`channel:manage:broadcast`). Sets content classification labels and the title, and fetches the stream key.
  - Refresh tokens are kept in Secrets (one secret per account, KMS), referenced from the DB.
- **Moderation tools**:
  - Cut to lounge (host, director, admin).
  - Moderator preview: live tracks in the lobby.
  - Guest controls: mute or remove audio, video and chat through LiveKit `UpdateParticipant` / `RemoveParticipant` and ninjamsrv `Kick`.
  - Destination kill switch.
  - Reports (from the lobby in M3; the hotel player in M5).
  - Audit for every action.
  - Terms and privacy policy published after legal review. Terms are re-accepted on a version bump.
- **Lobby additions**: room video page for players (live screens, talkback); moderator preview; broadcast control (destinations, talkback mix, start, stop, cut, kill); mix panel (host); recordings and opt-ins; destination connections.

### Terraform
- `modules/core`: stage, relay and lounge sizing; `presentation_slack_ms`; destination toggles.
- `modules/aws`:
  - **`room-region`**: room SG adds UDP 7882 in. Stage SG: egress only, plus rules allowing stage → room on 6379 and LiveKit's internal ports over the private IP. Task definition families `stage` and `room` (revised); `stage` execution and task roles (task role empty; scoped credentials come through the housekeeper).
  - **`media`** (home region and each relay region): ECR repos (`relay`, `lounge`); task definitions `relay` and `lounge`. Relay SG inbound SRT (UDP) and RTMP from room-region public prefixes (managed prefix lists of task IPs are impractical, so ingest auth is the **per-show SRT passphrase / stream key**) and from 443 for chathub (M5). Relay DNS `relay-<show>.<domain>` written by the launcher.
  - **`frontdesk`**: role adds `ecs:RunTask` for `stage`, `relay` and `lounge` (with PassRole), `secretsmanager:CreateSecret` / `PutSecretValue` / `DeleteSecret` on `hotel/dest/*` (tag-conditioned) and broader `room-scoped-media` session policies (video and show prefixes).
  - **Launcher**: generalized to the **task launcher** contract (`kind=room|stage|relay|lounge|works`), with per-kind DNS rules.

### API (M3)

**Media and mix**
- `POST /api/rooms/{id}/media-token` → LiveKit JWT. Grants by role: player publishes screen and mic; moderator subscribes to live tracks; director subscribes to `pc/*` and sends data on `director`. Ban checks run, device-bound for app clients.
- `PUT /api/rooms/{id}/mix {channels:[{user,ch,gain,pan,mute}]}`

**Destinations**
- `GET /api/me/destinations`
- `GET /api/oauth/{youtube|twitch}/start`
- `GET /api/oauth/{youtube|twitch}/callback`
- `DELETE /api/me/destinations/{id}`

**Broadcast**
- `POST /api/rooms/{id}/broadcast {destinations[], talkback_mix, lossless}`
- `DELETE /api/rooms/{id}/broadcast`
- `POST /api/broadcasts/{bid}/cut-to-lounge`
- `POST /api/broadcasts/{bid}/return`
- `POST /api/broadcasts/{bid}/destinations/{d}/{kill|restore}`

**Moderation and recordings**
- `POST /api/rooms/{id}/guests/{uid}/{mute|unmute|remove} {media:audio|video|chat}`
- `POST /api/reports`
- `GET /api/admin/reports`
- `POST /api/admin/reports/{id}`
- `GET /api/rooms/{id}/recordings`
- `PUT /api/rooms/{id}/members/me/recording-optin {screen, vj}`

**Internal**
- `POST /internal/broadcasts/{bid}/events`, used by the relay, stage and lounge: going live, switched, destination health.

### Data model (`0003_*`)
- `room_mix_versions(room_id, version, state jsonb, effective_index, set_by)`
- `destinations(id, account_id, platform, channel_id, display, secret_ref, scopes, status)`
- `shows(id, kind single|ballroom, region, status, presentation_slack_ms, created_by)`: every broadcast is a show (A11)
- `broadcasts(id, show_id, room_id, started_at, ended_at, lossless)`
- `broadcast_destinations(broadcast_id, destination_id, status, platform_ids jsonb)`
- `media_tasks(id, kind, show_id|room_id, task_arn, region, state)`
- `recordings(id, room_id|show_id, kind program|vj|screen, account_id, key, duration, status)`
- `recording_optins(room_id, account_id, screen, vj)`
- `moderation_actions(id, actor, target_account, room_id, action, media, at)`
- `reports(id, reporter, target, context jsonb, status, resolved_by)`

### State machines
- **Broadcast**: `off → starting (launch relay + lounge + stage; wait for SRT ingest healthy on both) → live ⇄ lounge_cut → stopping (stage stops; the relay drains destinations and closes HLS with ENDLIST; program.mp4 finalized) → off`.
- **Destination**: `connecting → live → (failed → retry with backoff ≤ 60 s) | killed → restored → live`.
- **Layout**: `grid ⇄ featured(p) ⇄ pip_vj`, evaluated only at PC boundaries, with hysteresis (two intervals). `manual(lease)` overrides until it is released or the lease expires.
- **delayline track**: `await_keyframe → filling (T + D − o_p) → releasing`. On a tempo segment change the delay is recomputed at the boundary; frames are dropped or held to re-anchor (never time-stretched). On a publisher restart it returns to `await_keyframe`.
- **mixbot interval**: `collect(k) → decode → mix (mix version at k) → publish at PC(k+1)`. In lossless mode: `fetch_flac(deadline) → fallback_vorbis(ch)` with the degradation recorded.

### Security boundaries
- LiveKit API key and secret are **per room**, generated at launch with HKDF from a master secret, so the front desk can mint tokens without storing per-room secrets and a room learns only its own.
- Media tokens last 10 minutes, are renewed by the client, and carry the device binding in their metadata for app clients.
- The stage task reaches only the room's private IP. Valkey requires its per-room password.
- SRT passphrase and stream key are per show, so the relay rejects anything else.
- Destination OAuth tokens: one Secrets Manager secret per destination. Only the front desk reads them; the relay receives just the RTMP URL and key, in memory, through its bootstrap.
- Moderator preview requires the site moderator or host role. The audit log covers every moderation action.

### Tests
- **syncscope (`tools/syncscope`)**: a bot player publishes a screen with a full-frame white flash at each beat while its audio carries a click at the same musical position. syncscope reads the relay's HLS or RTMP output and measures flash-to-click offset per beat. **Gate: |offset| ≤ 40 ms at p95, ≤ 80 ms max**, across BPM 60–200, BPI 4–32, a tempo change mid-show, lossless mode on and off, and player phase offsets −T/2..T/2.
- **Auto-switch**: scripted level patterns produce the expected layout at boundaries only (frame-accurate check on the output).
- **Seamless relay**: 50 consecutive switches (room ⇄ lounge) with no destination disconnect (YouTube stream health API: `good` throughout; Twitch ingest stays connected) and no PTS discontinuity in HLS.
- **Moderation**: cut to lounge from moderator preview lands before the content airs (asserted with syncscope markers); kill and restore a destination; guest mute and remove propagate to LiveKit and ninjamsrv within 1 s.
- **Network**: players behind a UDP-blocked, 443-only proxy connect through TURN/TLS via doorman.
- **Load**: a 5-player room plus 2 directors, 3 moderators and a VJ placeholder publisher (a bot). CPU under 70 % on the room task, and delayline memory measured.

### Cost and teardown
- Room task about $0.08/h compute plus data out ($0.3–1.2/h depending on layout).
- Stage task about $0.16/h. Relay about $0.08/h plus destination egress of about 2.7 GB/h per destination at 6 Mb/s (about $0.24/h each). Lounge about $0.16/h while a show runs.
- Every media task is launcher-managed with checkout and reaper coverage, and every task kind has a max lifetime.

### Definition of done ("synced stream")
- A five-player room streams publicly to YouTube and Twitch through the relay. syncscope passes the A/V gate for an hour, including a tempo change and lossless mode.
- Auto-switching cuts only on boundaries.
- Moderators preview live feeds, and cut-to-lounge, the kill switch and guest controls work.
- The terms (legally reviewed) are enforced at key issue.
- The as-aired program.mp4 and the opted-in track recordings land in the vault.
- The mixbot and delayline investigation reports are merged.

---

## M4 — Stagecraft (design gate: "VJ set airs")

### Components and final interfaces
- **Director view** (lobby):
  - Multiview of `pc/*` top layers.
  - Program monitor (the relay's low-latency preview, an SRT→WebRTC path from the switcher's preview output through the room LiveKit as a hidden track).
  - Layout and overlay picker (lower thirds, credits, titles).
  - "Take" (cut to a player or the VJ) and "auto" (hand back control).
  - Lease: one director holds control at a time; the host can take it over.
- **Show config**: overlays, templates and per-show branding are stored per show and read by the egress template.
- **VJ support in the app**:
  - **Clock out**: OSC (`/moonlight/{bpm,beat,bar,interval,phase}` at 100 Hz and on change), MIDI clock (24 ppqn plus SPP and start/stop at interval boundaries), and **Ableton Link** on the LAN (quantum = beats per interval at the chosen ratio, phase pinned). All of them run on the **audio-the-VJ-hears clock** (PC-aligned via the mix clock-map).
  - **Audio out**: the room mix to the **Moonlight Room Mix** virtual device:
    - macOS: an AudioServerPlugIn driver (`drivers/macos-hal`, installed in `/Library/Audio/Plug-Ins/HAL`) fed through shared memory.
    - Windows: a KMDF WaveRT virtual device (`drivers/windows-kmdf`, attestation-signed) fed through a shared-section IOCTL.
    - Linux: a PipeWire source node created by the app.
  - **Video bridges**:
    - Syphon (macOS): from Transmittal's IOSurface publisher, refactored to a GL-context-free Metal/IOSurface path.
    - Spout (Windows): Spout2 (BSD), DX11 shared textures.
    - NDI: through **ndi-helper**, a separate process taking frames over shared memory with a lock-step protocol.
    - Each bridge works in both directions: a VJ software output becomes the room VJ track, and room feeds come out as textures.
  - VJ track published natively with the clock-map stamped from the PC time the VJ hears.
- **OBS path**:
  - LiveKit **Ingress** (WHIP, transcoding bypassed) in the room task.
  - `POST /whip-token` issues a WHIP URL and bearer token.
  - A downloadable **OBS scene collection** (JSON) with a WHIP output preset, plus the app's OSC/MIDI clock and room-mix device usable as OBS sources.
  - OBS VJs are aligned by RTCP SR plus a one-time **clap calibration** in the app. OBS can't stamp the clock-map, so the app shows the measured offset and stores it per VJ device.
- **Link in the plugin**: when the player picks Link mode, the plugin (single-instance arbitration with the app) publishes a Link session at their ratio with the phase pinned to the local interval start. Link-capable DAWs follow, and phase source `link` is reported.
- **Clean VJ set recording**: TrackComposite in the stage task (already in M3), now fed by real VJ tracks.

### Terraform
- `modules/aws/room-region`: room task definition gains the `ingress` container (it needs Valkey). The room SG adds no new ports (WHIP goes through doorman on 443 with ALPN `h2`).
- `modules/aws/releases`: driver packages are signed. The macOS pkg installs the HAL driver with an `coreaudiod` restart prompt; the Windows installer installs the driver.
- `modules/core`: Link and clock defaults.

### API (M4)
- `PUT /api/rooms/{id}/director/lease`
- `DELETE /api/rooms/{id}/director/lease`
- `GET|PUT /api/shows/{id}/config {overlays, templates, branding}`
- `POST /api/rooms/{id}/whip-token`
- `GET /api/rooms/{id}/obs-profile`
- `PUT /api/me/devices/{id}/vj-calibration {offset_ms}`
- Director commands go over LiveKit data topic `director` (authorized by token grants): `take{target}`, `auto`, `layout{id}`, `overlay{id,on}`.

### Data model (`0004_*`)
- `director_leases(room_id, account_id, acquired_at, expires_at)`
- `show_configs(show_id, version, config jsonb)`
- `vj_calibrations(device_id, offset_ms, measured_at)`
- `whip_tokens(id, room_id, account_id, expires_at, used_at)`

### State machines
- **Director lease**: `auto ⇄ manual(holder)`. The host can preempt. The lease expires after 30 s without a heartbeat.
- **VJ source**: `none → app_native | obs_whip → calibrated → live → ended`.
- **Link arbitration**: `app_owns | plugin_owns(instance)`. Exactly one Link participant per machine.
- **Driver feed**: `disconnected → feeding ⇄ underrun(fill silence, counted) → disconnected`.

### Security boundaries
- WHIP tokens are single-use, scoped to the room and the VJ role, and ban-checked.
- ndi-helper runs as a separate unprivileged process, takes no network input except NDI, talks to the app over shared memory with a bounded ring, and is restarted by the app on crash.
- The drivers are minimal: no user-controlled buffer sizes in kernel space, fixed formats, IOCTLs validated, and the KMDF driver gets a Driver Verifier pass and an SDV/CodeQL-for-drivers pass.
- Director commands are honoured only from the lease holder (the template checks the sender identity against the lease state pushed by the housekeeper).

### Tests
- **VJ alignment through syncscope**: the VJ bot renders a flash on the beat it hears from the companion clock. On air, |flash − click| ≤ 40 ms at p95 for the native path, and ≤ 60 ms at p95 for OBS after calibration.
- **Clock outs**: OSC jitter < 2 ms; MIDI clock jitter < 1 ms (USB loopback measurement); a Link peer (a test app built on the Link SDK) sees the correct quantum and phase.
- **Drivers**: 8-hour soak without underruns at a 128-frame buffer; install, uninstall and upgrade; WHQL HLK tests where applicable to the attestation route.
- **Bridges**: round trip Syphon, Spout and NDI at 1080p60 into Resolume and TouchDesigner (manual matrix), and frame-hash verification with the test receiver.
- **Director**: lease contention, takeover, and auto-handback under scripted levels.

### Cost and teardown
- No new standing infrastructure. Ingress adds about 0.1 vCPU to the room task.

### Definition of done ("VJ set airs")
- In a public show, one VJ through the app (Syphon on macOS) and one through OBS WHIP perform, and a director takes and hands back control.
- The VJ sets air aligned within the gates, and the clean VJ set recording is in the vault.
- A Link-capable DAW follows the room through the plugin's Link mode, and Spout and NDI round trips are verified.

---

## M5 — Ballroom (design gate: "multi-act show")

### Components and final interfaces
- **Ballrooms**:
  - Line-up builder: acts, slot times, players per act, destinations, ticketing.
  - Publishing creates EventBridge **one-shot schedules** per set: green room at T−15, on-air at T, wrap at T+duration.
  - Aurora keep-warm: min ACU 0.5 from T−30 to the end of the show, through scheduled `ModifyDBCluster`.
- **Green room**: a room opened private with talkback on and no stage task. The stage task launches at T−2 minutes, so the relay has a warm input.
- **Relay switching**: at T the switcher switches to the new room (at that room's next PC boundary if within 1 interval, otherwise immediately). The outgoing room keeps playing until its set ends, then checks out. Between sets: the lounge.
- **Changeover uploads**: acts upload tracks for their changeover. The music priority follows the design.
- **Hotel player (lobby)**:
  - Persistent player bar (SPA shell) on all pages except rooms and lobbies.
  - Ballroom lobby page: synced playback (HLS `EXT-X-PROGRAM-DATE-TIME` aligned to server time), mute only, chat beside it.
  - Theater (replays), radio, track pages.
- **Media delivery**: the CloudFront distribution adds behaviors `/m/shows/*`, `/m/library/*` and `/m/radio/*` to the vault origin (OAC), restricted by a **key group** with signed cookies (ticketed or private) or signed URLs. The front desk signs with the key-group private key from Secrets.
- **Playback purpose**: `POST /api/playback {item, purpose: chosen|ambient}` returns a signed URL or cookie. `chosen` writes an access event only after a 30 s progress beacon (A30), unique per (listener, item, day).
- **Tickets**: Stripe Checkout (manual capture). The webhook checks the payment-layer ban (card fingerprint), then captures or cancels and issues the ticket. Refunds are admin-initiated.
- **Audience chat**: `chathub` in the relay task at `chat-<show>.<domain>` over WSS. Auth uses a session cookie exchange for a chat token. Moderators, slow mode, word filters and bans tie to the hotel ban list (account, email, device for app users, IP). Messages are persisted to Postgres in batches, and moderation actions are audited.
- **Libraries pipeline (works)**:
  - Checkout opt-in: the host is prompted, then each player and VJ (in the lobby, by email, and in the app), each for their own part. A per-part decision is recorded with the licence grant text version.
  - Mixdown: from consolidated stems with the **versioned mix state over time** (M3), normalized to −14 LUFS integrated (libebur128) with a −1 dBTP true-peak limit.
  - Fingerprint: Chromaprint against the **self-hosted AcoustID index** (A6). A match goes to an admin review.
  - Host trims and names the track. Publishing writes `library/muzak/<track-id>/` (FLAC master, Opus 128/320 renditions, credits.json) or `library/replays/<show-id>/` (MP4 masters and the HLS ladder).
  - Withdrawal deletes the master and renditions, unlists the item, and keeps frozen credits in the catalogue as "withdrawn".
- **AcoustID index**: a monthly **works job** rebuilds the index from the published dumps into an index file in S3. The fingerprint job memory-maps that file for lookups, so no standing server is needed.
- **Radio**: a server-side schedule of renditions (no task). Clients fetch the "now" position from `/api/radio/now` and play the rendition URLs with purpose ambient. Picking a track switches to chosen.
- **Night porter** (`job:night-porter`, nightly):
  - For each master in `media_objects`, it computes the target tier from `last_chosen_at` (or the room's end, for unpublished material) and the thresholds in `settings`.
  - Transitions:
    - Video: Standard → IA after 7 d, → Glacier Instant after 90 d, → Glacier Flexible after 1 y (unlist).
    - Audio: Standard → IA after 6 mo, → Glacier Flexible after 2 y (unlist).
  - Execution: CopyObject in place with the new StorageClass for objects ≤ 5 GB, UploadPartCopy multipart for larger ones, S3 Batch Operations when a night's set exceeds 1,000 objects.
  - Renditions are deleted when an item is unlisted. Stems follow their set's audio clock.
  - **Promote on chosen visit**: an IA or Glacier Instant master is copied back to Standard and its clock reset (event-driven, not nightly).
- **Archive restore**: a request (admin approval, or a threshold of N requests per month or year bucket) → S3 Batch Operations `RestoreObject` at Bulk tier with days=7 → `ObjectRestore:Completed` events → copy to Standard (multipart for over 5 GB) → works rebuilds the renditions → relisted with fresh clocks.
- **Catalogue**: metadata, credits, artwork and thumbnails stay in Standard, always browsable.

### Terraform
- `modules/core`: retention thresholds (defaults from the design), ticketing toggle, chat limits.
- `modules/aws`:
  - **`delivery`**: CloudFront public key and key group, vault origin with OAC (the vault bucket policy allows CloudFront only on `library/*/renditions/*`, `shows/*/hls/*` and `radio/*`), cache policies (HLS playlists 2 s, segments 1 y immutable), and an origin request policy carrying no cookies to S3. A response headers policy with CORS for the player.
  - **`vault`**: Batch Operations role (`s3:RestoreObject`, Get and Put inside the vault, PutObject on the reports prefix); EventBridge rules for `ObjectRestore:Completed`; an inventory configuration (daily, Parquet) feeding the night porter's reconciliation.
  - **`scheduler`**: the schedule-target role can `states:StartExecution` on the launcher in every room region and invoke `events`.
  - **`media`**: relay SG adds 443 for chathub; DNS `chat-<show>`.
  - **`frontdesk`**: Stripe secret and webhook secret in Secrets; `s3:CreateJob` and PassRole for Batch Operations; `rds:ModifyDBCluster` on the cluster (keep-warm), conditioned on the cluster ARN.
  - **`observability`**: alarms on the relay destination-health metric, HLS segment staleness, chathub errors and night porter failures.

### API (M5)

**Ballrooms and sets**
- `POST /api/ballrooms`
- `GET|PATCH /api/ballrooms/{id}`
- `PUT /api/ballrooms/{id}/sets`
- `POST /api/ballrooms/{id}/publish`
- `POST /api/ballrooms/{id}/cancel`
- `POST /api/sets/{id}/changeover-tracks` (presigned)
- `GET /api/shows/{id}`

**Playback and tickets**
- `POST /api/playback`
- `POST /api/playback/{pid}/beacon`
- `POST /api/shows/{id}/checkout` → Stripe session
- `POST /api/webhooks/stripe` (signature-verified)
- `GET /api/me/tickets`

**Chat**
- `POST /api/shows/{id}/chat-token`
- chathub WS: `join`, `send`, `delete`, `timeout`, `ban`, `slowmode`, `filter`

**Libraries and opt-ins**
- `GET /api/rooms/{id}/library-optin`
- `PUT /api/rooms/{id}/library-optin/me {audio, video, screen}`
- `PUT /api/library/tracks/{id} {title, trim_in, trim_out}`
- `POST /api/library/tracks/{id}/publish`
- `POST /api/library/{kind}/{id}/withdraw`
- `GET /api/library/muzak`
- `GET /api/library/replays`
- `GET /api/radio/now`

**Archive and admin**
- `POST /api/archive/restore-requests`
- `GET /api/admin/restore-requests`
- `POST /api/admin/restore-requests/{id}/approve`
- `GET /api/admin/fingerprint-reviews`
- `POST /api/admin/fingerprint-reviews/{id}`

### Data model (`0005_*`)
- **Ballrooms and shows**
  - `ballrooms(id, show_id, title, region, status)`
  - `sets(id, ballroom_id, room_id, act_name, slot_start, slot_end, status)`
  - `set_members(set_id, account_id, roles)`
  - `schedules(id, set_id, kind green|on_air|wrap|keepwarm, provider_ref, fire_at, status)`
  - `changeover_tracks(id, set_id, key, credits jsonb)`
- **Tickets**
  - `ticket_products(show_id, price, currency, capacity)`
  - `orders(id, account_id, show_id, stripe_session, payment_intent, status)`
  - `payment_fingerprints(account_id, fingerprint, seen_at)`, used by the payment ban layer
  - `tickets(id, order_id, account_id, show_id, status)`
- **Chat**
  - `chat_messages(show_id, id, account_id, body, at, deleted_by)`, retained for 90 days
  - `chat_settings(show_id, slow_mode_s, filters text[])`
- **Libraries**
  - `contributions(room_id, account_id, part audio|video|screen, decision, licence_version, decided_at, withdrawn_at)`
  - `library_items(id, kind muzak|replay, source_room|show, title, trim jsonb, status, published_at, withdrawn_at)`
  - `library_credits(item_id, account_id, frozen_artist_name, role)`
  - `fingerprint_results(item_id, matches jsonb, status, reviewed_by)`
- **Media and access**
  - `media_objects(key PK, item_id|room_id, kind master|rendition, media audio|video|stems, size, tier, listed, last_chosen_at, clock_origin, tier_changed_at)`
  - `access_events(listener_id, item_id, day, purpose, at)`, with a unique index on `(listener_id, item_id, day)` for chosen visits
  - `restore_requests(id, scope month|year, period, requested_by[], status, batch_job_id)`

### State machines
- **Ballroom**: `draft → published → live → ended | cancelled`.
- **Set**: `scheduled → green_room(T−15) → staging(T−2) → on_air(T) → wrapping (relay already switched; room plays out) → done`. A cancel leads to `cancelled`.
- **Relay input**: `lounge ⇄ room(set)` with a pre-roll health check: no switch to an input without a healthy SRT feed for 10 s; the lounge is held instead and an alert raised.
- **Opt-in (per room)**: `prompting (deadline 7 d) → decided_parts → pipeline`, or `expired` (treated as decline).
- **Library item**: `pending_consent → mixdown → fingerprint → (review) → awaiting_trim → published → withdrawn`.
- **Master tier**: `standard → ia → glacier_ir → glacier_flexible(unlisted) → restoring → standard`. Promotion goes `ia | glacier_ir → standard` on a chosen visit.
- **Order**: `created → authorized → (fingerprint banned → cancelled) | captured → ticketed → refunded`.

### Security boundaries
- CloudFront signed cookies are scoped to `/m/shows/<id>/*` and expire at show end plus a grace period. Replays use signed URLs (purpose-tagged). The vault is never public.
- The Stripe webhook verifies its signature, and it has the only code path that captures payment.
- chathub has the same token verification as the front desk and receives only its show's ban deltas.
- Night porter role: CopyObject inside the vault only. It cannot delete masters; only withdrawal deletes, through the front desk, and it is audited.
- Withdrawal and account deletion are audited and reversible for 7 days via versioning (noncurrent expiry).

### Tests
- **Ballroom end to end**: 3 acts of bot players, each in a different room region, with 10-minute slots. Green rooms open at T−15 (±10 s), switches happen at T, and the lounge runs between sets. YouTube stream health stays `good` throughout, there's no HLS discontinuity, and per-set programs are cut correctly from as-aired.
- **Hotel player**: ticket purchase in Stripe test mode. A banned card fingerprint is cancelled before capture. Signed-cookie scoping is checked: no access to another show.
- **Chat load**: 3,000 simulated chat clients (`tools/loadgen`) at 5 messages/s with slow mode. p95 fan-out under 500 ms and chathub CPU under 70 %.
- **Libraries**: mixdown loudness within ±0.5 LU of target; trim; fingerprint against a seeded copied recording leads to a review; withdrawal removes every object.
- **Retention**: time-travel tests with clock injection on a dedicated test prefix. Each tier transition and promotion is asserted. A real Bulk restore of a test object completes and relists.
- **Costs**: the S3 Storage Lens and Inventory reconciliation matches `media_objects.tier`.

### Cost (corrected model)

| Item | Approx. |
| --- | --- |
| Idle hotel | ~$60–65/month (+~$2/room region) |
| Jam room, not streaming | ~$0.10–1.30/h (compute ~$0.08 + data out by layout) |
| Streaming adds | stage ~$0.16/h + relay ~$0.08/h + ~$0.24/h per destination + lounge ~$0.16/h |
| Hotel player | ~$300–460/h at 3,000 viewers (CloudFront, as in the design) |
| Storage | as the design's per-show figures, after consolidation (A18) |

### Definition of done ("multi-act show")
- A published ballroom of at least three acts (in different regions) runs on schedule.
- It goes out to YouTube, Twitch and the hotel player (ticketed) with no destination drop, the lounge between sets, and moderated chat.
- After the show, opted-in work goes through the pipeline into the Muzak and replay libraries, which play in the theater and on the radio.
- The night porter tiers and promotes correctly, and a bulk restore relists archived items.

---

## P2 — Self-hosted (single VM)

### Components and final interfaces (adapter implementations)

| Interface | Implementation |
| --- | --- |
| Object store | **Garage** (AGPLv3), with tier capability `none` |
| Task launcher | Docker Engine API (rooms, stage, relay, lounge and works as labelled container groups); host resource admission control |
| Scheduler | In-process cron in the front desk, with a Postgres advisory-lock leader and one-shot jobs in a table |
| Email | SMTP |
| DNS | Static wildcard `*.rooms.<domain>` → VM IP (no per-room records), or RFC 2136 dynamic updates when configured |
| Secrets | Files (Docker secrets) or **OpenBao** |
| Edge blocklist | Caddy admin API deny rules |
| Realtime | Native WebSocket in the front desk, with Postgres LISTEN/NOTIFY across instances |
| Media delivery | Caddy `forward_auth` to the front desk, verifying HMAC-signed tokens and cookies |

- The front desk runs as a long-lived container (`serve` + `events` + cron).
- **Host doorman**: the same doorman binary in host mode routes `<room>.rooms…` by SNI to each room's internal doorman. Each room gets its own LiveKit UDP mux port from a pool, advertised in its room config.
- Caddy serves the lobby and terminates TLS for the lobby, front desk and `/m/*`.
- Postgres 16 runs as a container with WAL archiving to Garage.
- The ACME renewer works through RFC 2136 or the DNS adapter. A static DNS provider means a manual DNS-01 step, documented.

### Terraform
- **`modules/selfhosted`**: renders a cloud-init user-data document and a compose bundle (versioned images, env, secrets layout, Caddyfile, Garage config, systemd units for backups) from `modules/core` variables. Outputs: user-data, the DNS records to create, and firewall rules (443/tcp, the UDP port pool, SRT ports).
- Provider: **decision needed (A28)**. The proposal is provider-free, with documented examples for a few providers in `docs/`, not modules.

### API and data model
- No new endpoints.
- Adapter capability flags (for example `object_store.tiers=none`) are exposed in `GET /api/config`, so the lobby hides tier and restore UI.
- Migration `0006_*`: `scheduled_jobs(id, kind, fire_at, payload, leased_until)`.

### State machines
- **Launcher (Docker)**: `admit (CPU/RAM budget) → create containers → wait healthy → ready via housekeeper → open`. Failure leads to removal.
- The night porter is a no-op on tiers but still manages listing and renditions.

### Security boundaries
- The Docker socket is accessible only to the front-desk container's launcher through a **socket proxy that allows only a fixed API subset**, built into the front desk image as a separate process.
- Rooms run on per-room Docker networks with no inter-room routes.
- Secrets live in tmpfs.
- Host firewall rules come from Terraform outputs.

### Tests
- The **adapter contract suite** passes for every self-hosted adapter.
- The **full end-to-end suite of M1–M5 runs against a self-hosted VM in CI** (a nested VM on a self-hosted runner), with retention-tier tests skipped by capability.

### Cost and teardown
- One VM. Teardown is `docker compose down -v` plus VM deletion. Backups go to Garage, or off-host by the operator.

### Definition of done
- One `terraform apply` produces a user-data document that boots a fresh VM into a working hotel.
- The full M1–M5 suite passes there (minus tier capabilities), and the terms come as a template for operators.

---

## P3 — GCP

### Components and final interfaces (adapter implementations)

| Interface | Implementation |
| --- | --- |
| Object store | Native GCS adapter: V4 signed URLs; Nearline/Coldline/Archive, which are online, so "restore" is a rewrite to Standard and the tier FSM skips `restoring` |
| Task launcher | **Cloud Workflows** creating **GCE instances** from per-kind instance templates (Container-Optimized OS, container declaration, external IPv4/IPv6, Spot for works). Callbacks for readiness |
| Scheduler | Cloud Scheduler (cron jobs) plus **Cloud Tasks** with `scheduleTime` for one-shot set openings |
| Email | SMTP relay (the operator's) |
| DNS | Cloud DNS |
| Secrets | Secret Manager |
| Edge blocklist | Cloud Armor on the external Application Load Balancer |
| Realtime | Cloud Run native WebSocket, with LISTEN/NOTIFY fan-out |
| Media delivery | Cloud CDN signed cookies and URLs |

- The front desk runs on Cloud Run (min 0 instances, same image, `serve` mode).
- Postgres is Cloud SQL for PostgreSQL 16, with IAM DB auth through the Cloud SQL connector. It doesn't scale to zero (about $10–30 a month idle, documented).

### Terraform
- **`modules/gcp`**:
  - Project services; VPC with subnets per room region; firewall rules (443/tcp, UDP 7882, SRT).
  - Cloud Run service; Serverless VPC Access or Direct VPC egress; Cloud SQL.
  - GCS buckets (vault, lobby, releases) with uniform access and CMEK (Cloud KMS).
  - External HTTPS LB with backend buckets (lobby, media) and a serverless NEG (front desk); Cloud CDN; Cloud Armor policy.
  - Cloud DNS zones.
  - Workflows per region; instance templates per kind; Artifact Registry with remote replication.
  - Cloud Scheduler and Cloud Tasks queues.
  - Service accounts per principal (mirroring the M1 IAM split) with Workload Identity Federation for GitHub CI.

### API and data model
- No new endpoints. Migration `0007_*` only if adapter state needs it (Cloud Tasks names).

### State machines
- **Launcher (Workflows)**: `insert instance → poll RUNNING → read external IPs → Cloud DNS change → callback await (housekeeper ready) → open`. Failure leads to delete and fail.
- The tier FSM uses the online-archive variant.

### Security boundaries
- One service account per component, with no default compute SA.
- Room instances run with an SA with no roles (scoped credentials come through the front desk, as on AWS, using downscoped tokens via Credential Access Boundaries for GCS).
- Organization policy: restrict regions, disable SA key creation.

### Tests
- The adapter contract suite against real GCP, plus the full M1–M5 suite against a GCP deployment.

### Cost and teardown
- Idle is about $40–70 a month (Cloud SQL, LB forwarding rule about $18, Armor). `terraform destroy` is clean in the test project.

### Definition of done
- The full suite passes on GCP. Rooms run in at least two GCP regions, and a multi-act ballroom airs from GCP.

---

## P4 — Azure

### Components and final interfaces (adapter implementations)

| Interface | Implementation |
| --- | --- |
| Object store | Native Blob adapter: user-delegation SAS (PUT requires `x-ms-blob-type`, carried in the grant's per-URL headers from M2); access tiers Hot/Cool/Cold/Archive; rehydrate at Standard priority |
| Task launcher | **Azure Container Instances** container groups with public IPs and UDP ports, orchestrated by **Logic Apps (Standard)** workflows with a readiness callback |
| Scheduler | Logic Apps recurrence for cron jobs, plus Service Bus scheduled messages for one-shots, consumed by the front desk `events` endpoint |
| Email | SMTP relay (or Azure Communication Services Email, if the operator chooses; it's a cloud service behind the adapter) |
| DNS | Azure DNS |
| Secrets | Key Vault |
| Edge blocklist | Front Door WAF custom IP rules |
| Realtime | Container Apps native WebSocket, with LISTEN/NOTIFY |
| Media delivery | **Front Door has no signed-cookie verification**. The design adopted: playlists are served by the front desk (it checks the cookie and rewrites segment URIs to an unguessable per-show, per-day prefix); segments are cached at Front Door under that prefix, which rotates daily. This is a weaker guarantee than CloudFront, documented in the operator guide |

- The front desk runs on Azure Container Apps (scale to zero).
- Postgres is Azure Database for PostgreSQL Flexible Server (Burstable), with Entra ID auth.
- ACI IPv6 support is limited, so rooms are IPv4-only on Azure (documented). The /64 IP ban layer still applies to v6 clients at Front Door.

### Terraform
- **`modules/azure`**:
  - Resource groups; VNets per room region; NSGs; Container Apps environment; PostgreSQL Flexible.
  - Storage accounts (vault, lobby, releases) with CMK in Key Vault.
  - Front Door Standard/Premium with WAF policy; Azure DNS zones.
  - Logic Apps Standard; Service Bus namespace.
  - Azure Container Registry with geo-replication.
  - User-assigned managed identities per principal (mirroring M1 IAM), and federated credentials for GitHub OIDC.

### API and data model
- No new endpoints. Migration `0008_*` for Service Bus sequence numbers, if needed.

### State machines
- **Launcher (Logic Apps)**: `create container group → poll Running → read IP → DNS record → await callback → open`. Failure leads to delete.
- The tier FSM uses the Blob variant (Archive requires rehydration: `restoring`).

### Security boundaries
- One managed identity per component. Room container groups have no identity (scoped user-delegation SAS through the front desk).
- Key Vault RBAC. Private endpoints for PostgreSQL and Key Vault from the Container Apps environment.

### Tests
- The adapter contract suite against real Azure, plus the full M1–M5 suite (media-delivery assertions adapted to the documented guarantee).

### Cost and teardown
- Idle is about $60–90 a month (Front Door base about $35, PostgreSQL Burstable about $15, Container Apps idle about $0). Resource group deletion gives full teardown in test.

### Definition of done
- The full suite passes on Azure, and a multi-act ballroom airs from Azure. The media-delivery guarantee is documented.

---

## Verification (across the whole programme)
- **Every milestone's DoD is a CI job** (`.github/workflows/gate-mN.yml`) that deploys to staging (or the P-target), runs the end-to-end suite with moonlight-bot, syncscope and loadgen, records artefacts (sync histograms, launch timings, cost-per-hour from Cost Explorer tags), and tears down.
- **Adapter contract suites** are the portability proof: a cloud is "done" when its adapters pass the same suite AWS passes, and the M1–M5 gates pass unchanged on it.
- **Licence gate** on every PR (M0). **Gate regressions block merges**: earlier milestones' gate suites keep running nightly.

## Execution notes
- Creating the public GitHub repo, the AWS Organizations accounts, and any registrar or DNS delegation are outward-facing steps. I'll confirm each before acting.
- Investigations (uploader, mixbot, delayline) can start in parallel with earlier work once `ninjam/core` exists, but no dependent component merges before its investigation report.
