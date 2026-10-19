# Kickoff prompt for the planning session

Open Claude Code in this folder (`moonlight-hotel/`), switch to plan mode, and paste the prompt below.

---

Read `docs/DESIGN.md` in full, starting with "How this gets built". It is the system design for The Moonlight Hotel, an open-source (AGPLv3) platform owned by Moon Technologies LLC for interval-synced online jamming from any DAW, built on NINJAM, with VJs, directors, live streaming, festival scheduling and media retention, deployed AWS-first with Terraform and later to self-hosted, GCP and Azure.

**Read this before planning anything:**

- There is no MVP, no v1, no proof of concept and no deadline. I am not shipping to anyone on a schedule. Do not optimize for time to first result.
- Plan the entire system as described, every milestone at the same depth. Do not detail one milestone and outline the rest.
- No shortcuts of any kind: no stand-ins, no "for now", no temporary workarounds, no stub that a later milestone replaces, no third-party product standing in for a hotel component, no SaaS. If something is in the design, it is built as its final version.
- NINJAM is the foundation, and the hotel owns both sides: its own client (the Moonlight app and plugin) and its own server, both built from NINJAM's source. Never plan around JamTaba, ReaNINJAM or any other third-party NINJAM client, including for testing.
- Milestones are build order forced by dependencies, not release cuts. Each milestone's output is finished, production-grade parts of the final system.
- If you believe a design choice is wrong, say so and propose the better final design. Do not propose a smaller or simpler version as a way to get something running sooner.

**Constraints and context:**

- New monorepo, `drphilibuster/moonlight-hotel`, laid out as in the design's "Repository layout". Repository initialization (licence, CLA, CI, README) is the first build step.
- Terraform for all infrastructure, split into `infra/modules/core` and `infra/modules/aws`; every cloud-specific call sits behind the seven adapter interfaces in the design.
- Control plane: one containerized front desk service on Lambda via Lambda Web Adapter, static lobby on S3 + CloudFront at moonlighthotel.com (domain owned, no infrastructure yet), Postgres on Aurora Serverless v2 with scale-to-zero. Accounts are persistent from first contact (magic link plus passkeys), and a complete artist profile is required before anyone can take part. Bans are layered (account, email, passkey, device, IP, payment) and enforced at every entry point, including the hotel server's connect handshake.
- Rooms: one Fargate task per room, launched on demand by Step Functions, torn down by an idle housekeeper.
- Tempo is set by the host in the lobby only; the housekeeper applies it to the hotel server as a privileged system user.
- First task: audit NINJAM's source licence headers (GPLv2-only vs v2-or-later). Every client and server component depends on the answer.
- The riskiest new code (`mixbot`, `delayline`, the plugin's lossless uploader) gets a dedicated engineering investigation before the components that depend on it, and that investigation's code is the real component, not a throwaway.
- Existing related code: MoonVerb (JUCE plugin, `drphilibuster/moonverb-vst`, local `../MoonVerb/`, pins JUCE 9.0.3; follow its JUCE version) and the Syphon publisher in the MoonTechnologies repo (`src/Transmittal/`).
- I'm an AWS Certified Solutions Architect – Professional; skip basics, be explicit about IAM boundaries, networking, cost and teardown.

For each milestone, include: components and their final interfaces, Terraform resources by module, API endpoints and data model changes, state machines, security boundaries, tests, and a definition of done that matches the milestone's gate in the design.

Flag anything in the design that is ambiguous, or that you disagree with, before planning around it.
