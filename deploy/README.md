# Single-Droplet deployment

Experimental audio service, not a production-ready LiveKit replacement.
Target: Ubuntu 24.04, 1 vCPU / 2 GB RAM, no backups. The initial admission
limits are five rooms and twenty sessions; these are not measured capacity.

1. Point the hostname's DNS A record directly at the server (no HTTP proxy).
2. Install Docker Engine and Compose. Allow TCP 22, 80, 443 and UDP
   50000–50100 in the firewall. TURN also needs TCP/UDP 3478 and UDP
   49160–49200. Do not expose 4000 or Erlang distribution ports.
3. Copy this repository to `/opt/webrtc-live`.
4. Run `sh deploy/init-env.sh`, then set the hostname and public IPv4 address
   in `.env`. This generates separate signing and TURN secrets. Keep `.env`
   private (`chmod 600 .env`) and never commit it.
5. Configure Brevo and PostgreSQL, then follow the build/migrate/start sequence
   in [AUTH.md](AUTH.md). Linux host networking allows ICE to advertise the
   server's real public address. HTTP and PostgreSQL bind only to loopback.
6. Verify `curl https://YOUR_HOST/health` returns `ok`, and `/dev/token`
   rejects token requests. Caddy obtains and renews trusted certificates;
   retain its Docker volumes across updates.

## Manual call

Generate a grant over SSH from `/opt/webrtc-live`:

```sh
docker compose exec -T app bin/webrtc_live rpc 'WebRTCLive.Access.issue("demo", "alice", "participant") |> elem(1) |> IO.puts()'
```

Open `/index.html` on the HTTPS site, select room `demo`, role **Talk and listen** (`participant`), and paste the
token. Generate another token with identity `bob` for the other client.
Join within five minutes of issuance. Never share the server secret.

From the local checkout, with npm dependencies installed, run the two-client
smoke test (real HTTPS, synthetic microphones, no load test):

```sh
BASE_URL=https://webrtc.efrenfuentes.net DEPLOY_SSH_HOST=codex-keen-dusk-76f6 node test/browser/deployed-smoke.mjs
```

## Operations and limits

`docker compose ps` shows services, `docker compose logs --tail=100` shows
recent logs. Follow [AUTH.md](AUTH.md) to deploy updates and migrations; restarting
the app ends all calls. Accounts, sessions, and room permissions are persistent.
There are no recordings. Back up the database and never remove its Docker volume.

## TURN

Existing installations: run `sh deploy/enable-turn.sh` once before updating.
This adds a random TURN secret without changing the token signing secret.
Open TCP/UDP 3478 and UDP 49160–49200, then rebuild with Compose. Updating
the app interrupts active calls.

Authenticated `/config` responses include 24-hour HMAC TURN credentials tied
to the token identity. The shared secret is never sent to the browser. The
server's own ICE configuration is unchanged: only browsers need the relay.
Credentials are bearer grants, not revocable or room-scoped; renew by rejoining
with a fresh admission token before 24 hours. Automatic renewal is not implemented.

Coturn accepts UDP and TCP client transports on port 3478 and relays only to
the Droplet's public IP. Other IPv4/IPv6 peers (including private/metadata IPs)
are denied. Allocation limits are 4 per TURN user and 40 total; bandwidth is
capped at 256,000 bytes/s per allocation and 5,120,000 bytes/s aggregate in
each direction. These are safety limits, not measured capacity. WebRTC media
remains DTLS-SRTP encrypted. TURN TLS/443 is not configured, so networks allowing
only HTTPS traffic can still fail; do not claim universal connectivity.

Verify both relay transports from an external client:

```sh
BASE_URL=https://webrtc.efrenfuentes.net DEPLOY_SSH_HOST=codex-keen-dusk-76f6 TURN_TRANSPORT=udp node test/browser/deployed-smoke.mjs
BASE_URL=https://webrtc.efrenfuentes.net DEPLOY_SSH_HOST=codex-keen-dusk-76f6 TURN_TRANSPORT=tcp node test/browser/deployed-smoke.mjs
```

These tests force relay-only ICE, verify the selected candidate and transport,
and require decoded audio in both directions. Omit TURN_TRANSPORT for the
normal connection test. Use additional real networks before wider use.

Initial short load tests passed at five four-person rooms over direct audio
and TURN UDP/TCP. Ten direct rooms hit the server/generator CPU safety stop;
the production limit remains five rooms. See the
[results and limitations](../test/browser/LOAD_RESULTS_2026-09-21.md).
Long-duration capacity validation remains. Invite-only account authentication and
session-bound browser grants are implemented; service grants and TURN credentials
remain bearer capabilities. Network abuse protection remains incomplete. Monitor CPU, memory, bandwidth,
and DigitalOcean billing. Stopping the server does not stop Droplet billing;
delete it when no longer needed. Transfer overages may add to the base price.
