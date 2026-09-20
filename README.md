# WebRTCLive

An Elixir WebRTC SFU prototype. The first milestone relays **Opus audio from one
publisher to one listener** through the server. It is not LiveKit-protocol compatible.

## Run locally

```sh
mise install
mix deps.get
mix phx.server
```

Open <http://localhost:4000> in two browsers or tabs. Join as **Publish microphone**
in one and **Listen** in the other, using the same room name. Allow microphone
access and use headphones. Either role can join first. If autoplay is blocked,
use the audio player's play button. The publisher can mute/unmute without
renegotiation. Each room admits only one participant of each role. Use different
participant identities. Leave the token field blank for automatic local demo tokens.

Leaving or closing a tab cleans up its peer connection. When a publisher leaves,
the listener's session ends too; join again to start a new session. After a signaling
failure, reconnect manually with Join. Empty rooms are removed automatically.

## Architecture

- Phoenix Channels negotiate SDP and exchange trickled ICE candidates.
- `ex_webrtc` terminates ICE, DTLS and SRTP and handles Opus RTP transport.
- A Registry and DynamicSupervisor own ephemeral room GenServers.
- Rooms manage membership, monitor participants, and give the publisher its
  destination. RTP is forwarded directly to the listener's peer connection,
  without crossing the room process or Phoenix PubSub. There is no transcoding.
- The demo uses native browser WebRTC and Phoenix's bundled JavaScript client;
  no frontend build or CDN is required.

## Checks

```sh
mix format --check-formatted
mix test
```

The optional browser test uses two isolated Chromium contexts with synthetic
microphone audio. With the server running in another terminal:

```sh
npm ci
npm run test:browser
```

Set `CHROMIUM_PATH` if Chromium is not at `/usr/bin/chromium`. This checks actual
received RTP and decoded audio energy, playback, mute, duplicate admission,
both join orders, leave/rejoin, and tab-close cleanup. Node is only needed for
this optional test, not to run the app.

## Access and resource limits

All WebSocket connections require a signed access token. A grant contains a room,
participant identity, and role (`publisher` or `listener`). The signature and
five-minute lifetime are checked on connect and again on room join. Expiry limits
admission, not the duration of an established call. Tokens are bearer credentials
and can be reused within that window; they are not single-use or revocable yet.
The same identity cannot occupy both roles in a room.

These are Phoenix signed tokens, **not JWTs or LiveKit-compatible tokens**. Issue
them from trusted Elixir application code after authenticating your own users:

```elixir
{:ok, token} = WebRTCLive.Access.issue("demo", "alice", "publisher")
```

For local manual testing, `iex -S mix phx.server` starts a server with an interactive
shell where you can run that expression. Paste its token into the demo. The signed
identity is authoritative; the Identity field is used only when requesting a demo token.
`POST /dev/token` issues unrestricted demo grants only in development; it returns
404 in test and production. There is no public production token-minting endpoint.
`GET /config` also requires a bearer token to protect TURN credentials and sends
`Cache-Control: no-store`. Use HTTPS and redact WebSocket token query parameters
from proxy access logs. Phoenix filters token parameters from its own logs.

Defaults in `config/config.exs`:

- 100 rooms and 200 reserved/active media sessions per node.
- One publisher, one listener, and one directional audio track per participant.
- A 30-second deadline to establish the media connection.
- 100 signaling messages per participant per 10-second window; excess closes the session.
- 128 KiB WebSocket frames, SDP below 64 KiB, and ICE candidate strings below 4 KiB.

Reservations are atomic and released when the channel exits, including crashes.
Supervisor restarts also tear down dependent sessions to keep limits consistent.
These are initial application limits, not comprehensive network abuse protection.

## Network configuration

Development binds to loopback on port 4000 with no external ICE servers.
Microphone capture requires localhost or HTTPS. A remote deployment also needs
reachable WebRTC UDP ports and usually TURN for restrictive networks.

`ICE_SERVERS_JSON` configures the browser and server, for example:

```sh
ICE_SERVERS_JSON='[{"urls":"stun:stun.example.com:3478"},{"urls":"turn:turn.example.com:3478","username":"demo","credential":"temporary-password"}]' mix phx.server
```

These credentials are exposed to the browser by `/config`; use temporary,
restricted TURN credentials. For production mode, `HOST` and `SECRET_KEY_BASE`
are required, with HTTPS terminated at a reverse proxy. `PORT` defaults to 4000.

## Scope and next steps

This is a local development milestone, **not ready for public deployment**.
Signed admission and application resource limits are implemented. User account
authentication, token revocation, per-account quotas, HTTP/connection rate limiting,
and cross-network TURN testing remain. Rooms and calls are lost on restart.
It does not implement video, bidirectional conferencing, automatic reconnect,
recording, simulcast, congestion adaptation, or the LiveKit SDK protocol.

Next: bidirectional audio with 2–4 participants and a TypeScript SDK; then video, TURN verification
across networks, and deployment hardening.
