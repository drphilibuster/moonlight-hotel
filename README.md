# The Moonlight Hotel

An open-source venue where musicians play together over the internet from their
own DAWs, VJs and directors shape the picture, and the result streams live to an
audience. It runs as a hosted service at moonlighthotel.com, and anyone can
deploy the whole suite into their own cloud.

The hotel is built on [NINJAM](https://www.cockos.com/ninjam/)'s interval model:
everyone hears everyone one interval late, so distance stops mattering. The
hotel owns both sides of it — its own client (the Moonlight app and plugin) and
its own server — built from NINJAM's source.

- **Design:** [docs/DESIGN.md](docs/DESIGN.md)
- **Build plan:** [docs/planning/build-plan.md](docs/planning/build-plan.md)
- **Licensing:** [docs/licensing/](docs/licensing/)

## Status

Milestone M0: repository and licence audit. Nothing here runs yet.

## Licence

AGPLv3 or later, copyright Moon Technologies LLC. See [LICENSE](LICENSE) and
[COPYRIGHT](COPYRIGHT). Anyone running a modified version of the hotel as a
network service must offer its users the corresponding source (AGPLv3 §13);
every hotel service reports the commit it was built from for that purpose.

Third-party components keep their own licences; see [NOTICE](NOTICE).

## Contributing

Contributions need a signed Contributor Licence Agreement — see
[CONTRIBUTING.md](CONTRIBUTING.md). Security reports: [SECURITY.md](SECURITY.md).
