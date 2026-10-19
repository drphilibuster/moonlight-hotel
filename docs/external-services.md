# External services

The hotel builds every component itself and runs only self-hostable software.
A few things can't be self-built. Each sits behind an interface in the front
desk, and this is the complete list. Adding to it needs a design change.

| Service | What for | Why it can't be self-built | Interface | From |
| --- | --- | --- | --- | --- |
| Stripe | Ticket payments, card fingerprints for the payment ban layer | Card processing requires a licensed payment processor | `payments` | M5 |
| YouTube Data API | Create live broadcasts, set age restriction and made-for-kids, write performer descriptions | It is the destination platform | `destinations/youtube` | M3 |
| Twitch Helix API | Stream key, title, content classification labels | It is the destination platform | `destinations/twitch` | M3 |
| Let's Encrypt (ACME) | The `*.rooms` wildcard certificate | A publicly trusted CA is required | ACME client in `job:certs` | M1 |
| Apple notarization | macOS app, plugin and driver distribution | Gatekeeper requires Apple's notary | release tooling | M2 |
| Microsoft attestation signing | Windows virtual audio driver | Windows requires Microsoft-signed kernel drivers | release tooling | M4 |
| Avid / PACE signing | AAX release builds | Pro Tools loads only PACE-signed AAX plugins | release tooling | M2 |
| Cloud providers | AWS (phase 1), then GCP and Azure | The deployment targets themselves | the nine cloud adapters | M1 |

Not on this list on purpose:

- **AcoustID's web API.** Its free tier is non-commercial and it's a SaaS. The
  hotel runs the AcoustID index itself from published data dumps (M5).
- **Any third-party NINJAM client**, for any purpose, including testing.
- **Hosted CLA services.** The CLA bot is a GitHub Action that stores
  signatures in this repository.
