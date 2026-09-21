# Single-Droplet deployment

Experimental audio service, not a production-ready LiveKit replacement.
Target: Ubuntu 24.04, 1 vCPU / 2 GB RAM, no backups. The initial admission
limits are five rooms and twenty sessions; these are not measured capacity.

1. Point the hostname's DNS A record directly at the server (no HTTP proxy).
2. Install Docker Engine and Compose. Allow TCP 22, 80, 443 and UDP
   50000–50100 in the firewall. Do not expose 4000 or Erlang distribution ports.
3. Copy this repository to `/opt/webrtc-live`.
4. Copy `.env.example` to `.env`, set the hostname and public IPv4 address,
   and replace `SECRET_KEY_BASE` with `openssl rand -hex 64`. Keep `.env`
   private (`chmod 600 .env`) and never commit it.
5. Run `docker compose up -d --build`. Linux host networking allows ICE to
   advertise the server's real public address. HTTP binds only to loopback.
6. Verify `curl https://YOUR_HOST/health` returns `ok`, and `/dev/token`
   rejects token requests. Caddy obtains and renews trusted certificates;
   retain its Docker volumes across updates.

## Manual call

Generate a grant over SSH from `/opt/webrtc-live`:

```sh
docker compose exec -T app bin/webrtc_live rpc 'WebRTCLive.Access.issue("demo", "alice", "participant") |> elem(1) |> IO.puts()'
```

Open the HTTPS site, select room `demo`, role **Talk and listen** (`participant`), and paste the
token. Generate another token with identity `bob` for the other client.
Join within five minutes of issuance. Never share the server secret.

From the local checkout, with npm dependencies installed, run the two-client
smoke test (real HTTPS, synthetic microphones, no load test):

```sh
BASE_URL=https://webrtc.efrenfuentes.net DEPLOY_SSH_HOST=codex-keen-dusk-76f6 node test/browser/deployed-smoke.mjs
```

## Operations and limits

`docker compose ps` shows services, `docker compose logs --tail=100` shows
recent logs. Deploy updates with `docker compose up -d --build`; restarting
the app ends all calls. No recordings or persistent room data exist.

This initial setup has no TURN relay. Direct UDP calls may fail on restrictive
networks; TURN and cross-network testing remain required before wider use.
No load testing has been performed. Account authentication, token revocation,
and network abuse protection remain incomplete. Monitor CPU, memory, bandwidth,
and DigitalOcean billing. Stopping the server does not stop Droplet billing;
delete it when no longer needed. Transfer overages may add to the base price.
