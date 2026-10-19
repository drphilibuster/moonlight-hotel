# Business prerequisites

Things only Moon Technologies LLC can do, and the milestone each one blocks.
Build work proceeds up to the gate; the gate can't pass until the item is done.

| Item | Needed for | Blocks | Notes |
| --- | --- | --- | --- |
| Registrar NS delegation of moonlighthotel.com to Route 53 | Lobby, API, rooms DNS | M1 | Done after the `dns` module is applied |
| Mailboxes for legal@, conduct@, security contact | Repository policies, CLA-ENTITY | M1 | SES receipt rules, or the LLC's mail provider |
| SES production access | Magic links and invites to unverified addresses | M1 | Request in the prod account |
| AWS Organizations (management, prod, staging, log-archive) | All infrastructure | M1 | Owned by the LLC |
| D-U-N-S number → Apple Developer Program (organization) | Developer ID signing, notarization | M2 | Organization enrollment requires D-U-N-S |
| EV code-signing certificate | Windows app and installer signing | M2 | Also needed for driver attestation (M4) |
| Avid developer agreement, PACE/iLok account | Signed AAX builds | M2 | After confirming the AAX SDK terms allow an AGPL plugin (licence audit) |
| Microsoft Partner Center (hardware program) | Attestation-signed Windows driver | M4 | Needs the EV certificate |
| Google OAuth app verification, YouTube API quota increase | Creating broadcasts on users' channels | M3 | `youtube.force-ssl` is a sensitive scope |
| Twitch developer application | Twitch destinations | M3 | |
| YouTube and Twitch channels owned by the LLC | The hotel's own outlets | M3 | |
| Legal review: terms, privacy policy, CLA, library licence | First public show | M3 | Library licence before M5 pipelines publish |
| EIN → Stripe account | Tickets | M5 | |
