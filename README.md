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
renegotiation. Each room admits only one participant of each role.

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
Room names are not authentication: there are no signed access tokens, authorization,
quotas, rate limits, or room-count limits yet. Rooms and calls are lost on restart.
It does not implement video, bidirectional conferencing, automatic reconnect,
recording, simulcast, congestion adaptation, or the LiveKit SDK protocol.

Next: signed room/identity/permission tokens and resource limits; bidirectional
audio with 2–4 participants and a TypeScript SDK; then video, TURN verification
across networks, and deployment hardening.
