# Authentication operations

The app uses Phoenix-generated accounts, PostgreSQL-backed sessions, and Brevo
transactional email. Sign-up is invitation-only. Every invited user can create
rooms and invite people to rooms they own. The bootstrap administrator flag is
reserved for future administration features; it does not bypass room membership.

Owners can delete rooms from the room list or room page after a separate
confirmation. Active rooms must be emptied first. Deletion removes memberships,
not user accounts. Browser grants include the database room ID so old grants
cannot become valid again when a room name is reused. Authenticated joins and
deletion use database row locks to avoid deleting a room while a join is admitted.
Trusted service tokens remain an administrator-controlled diagnostic capability.

Set `POSTGRES_PASSWORD`, `DATABASE_URL`, and `BREVO_API_KEY` in the server's
private `.env` (mode 0600). Never commit real values. The verified Brevo sender
must be `developer@efrenfuentes.net`. Keep link tracking disabled for login emails.
Rotate any key shared in a conversation after setup, then recreate the app
container so it receives the replacement.

## Deploy

From `/opt/webrtc-live`, after copying application source:

```sh
docker compose up -d db
docker compose build app
docker compose run --rm --no-deps app bin/webrtc_live eval 'WebRTCLive.Release.migrate()'
docker compose up -d app
```

Bootstrap the first administrator and send a 15-minute, single-use login link:

```sh
docker compose exec -T app bin/webrtc_live rpc 'IO.inspect(WebRTCLive.Release.invite_admin("efrenfuentes@gmail.com"))'
```

`:ok` means Brevo accepted the message, not that it reached the inbox. The same
command can resend to the existing administrator. It will not promote an existing
ordinary account or bootstrap a different administrator once one exists.
After login, the administrator can create a room and send invitations from it.
Subsequent login links are requested at `/users/log-in`. Passwords are optional
and can be configured in Settings after a recent login.

Browser grants last five minutes, are tied to a valid login session, and enforce
membership and role on socket connection and room join. Logout disconnects that
session's sockets and revokes its grants. Changing a membership affects future
joins; it does not change an already-connected participant's role. Trusted
server-side `Access.issue/3` service tokens remain available for SDK integrations
and diagnostics at `/index.html`; there is no public production issuer.

Limits are in-memory on this single app process: 30 modifying browser requests
per actor per minute, plus three login requests per email per minute. Restarting
the process resets them. Caddy on loopback is the only trusted forwarding proxy.
This is not a distributed rate limiter.

## Database backup and restore

PostgreSQL is private on `127.0.0.1:5433`, with a persistent Docker volume.
Never run `docker compose down -v`: it deletes accounts and room permissions.
The $12 Droplet still has **no automatic or off-server backups**.

Create a manual backup and copy it securely off the Droplet:

```sh
umask 077
docker compose exec -T db pg_dump -U webrtc_live -d webrtc_live -Fc > accounts.dump
```

Restore only into an empty replacement database with the app stopped:

```sh
docker compose exec -T db pg_restore -U webrtc_live -d webrtc_live --no-owner < accounts.dump
```

Keep `.env` separately encrypted, and protect dumps as sensitive account data.
Test restores before relying on a backup. Database migrations here are additive;
rolling back the app image should leave the database and its volume intact.

## Local development and verification

Provide PostgreSQL on port 5433 (default user/password `postgres/postgres`), or set
`DATABASE_URL`. Then run `mix ecto.create`, `mix ecto.migrate`, and `mix phx.server`.
The development-only mail preview is `/dev/mailbox`. Seed a local first account
with `WebRTCLive.Release.invite_admin/1` from `iex -S mix phx.server`.

For tests, create/migrate with `MIX_ENV=test`, then run `mix test`. Browser checks:

```sh
node test/browser/auth-smoke.mjs
npm run test:browser
BASE_URL=https://webrtc.efrenfuentes.net DEPLOY_SSH_HOST=codex-keen-dusk-76f6 node test/browser/auth-smoke.mjs
```

The auth smoke test creates two temporary accounts without sending mail, logs in
through the browser, checks two-way audio and CSRF, then removes its test records.
The legacy media harness intentionally uses `/index.html` with trusted test tokens.
