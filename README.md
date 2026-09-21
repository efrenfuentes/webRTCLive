# WebRTCLive

An Elixir WebRTC SFU prototype with **bidirectional Opus audio for up to four
participants per room**, signed access grants, and a small TypeScript SDK.
It is not LiveKit-protocol compatible.

## Run locally

```sh
mise install
mix deps.get
mix phx.server
```

Open <http://localhost:4000> in two to four browsers or tabs. Join as **Talk and listen**
using the same room name and distinct identities. Allow microphone access and use
headphones. If autoplay is blocked, use each participant's audio player. Mute state
is visible to everyone. **Publish only** and **Listen only** remain available for
restricted grants. Leave the token field blank for automatic local demo tokens.

Leaving or closing a tab cleans up that participant without interrupting others.
Vacated slots can be reused immediately. After a signaling failure, reconnect
manually with Join. Empty rooms are removed automatically.

## Architecture

- Phoenix Channels negotiate SDP and exchange trickled ICE candidates.
- `ex_webrtc` terminates ICE, DTLS and SRTP and handles Opus RTP transport.
- A Registry and DynamicSupervisor own ephemeral room GenServers.
- Rooms assign four stable slots, monitor participants, and distribute routing
  snapshots. Participants forward RTP directly to other participants' channel
  processes, where it is mapped to outgoing tracks; media does not cross the
  room process or PubSub. There is no transcoding or self-audio forwarding.
- One browser/server PeerConnection negotiates one microphone transceiver and
  four receive transceivers. Inactive/self slots carry no audio. Membership changes
  need no renegotiation; per-slot RTP sequence/timestamp translation maintains
  continuity when a different source takes a vacated slot, including elapsed silence.
- The demo imports the bundled TypeScript SDK from `/sdk.js`. The generated bundle
  is checked in, so running the app needs neither Node nor a CDN.

## Browser SDK

`sdk/src/index.ts` exports `Room`, `JoinOptions`, `Participant`, `RemoteAudio`, and
`Role`, and `RoomEvents`. The SDK owns microphone capture, signaling, ICE, media,
and cleanup. `room.on(event, handler)` provides typed events and returns an unsubscribe
function; standard `addEventListener` also works:

```js
import { Room } from "/sdk.js";
const room = new Room();
room.on("participants", (participants) => console.log(participants));
room.on("tracks", () => {
  // Reconcile your audio elements using participant.identity as the key.
  for (const { participant, track } of room.remoteAudio) {
    // audio.srcObject = new MediaStream([track]);
  }
});
room.on("state", (state) => console.log(state));
await room.join({ room: "demo", token, role: "participant" });
await room.setMuted(true);
room.leave();
```

`join()` resolves when SDP negotiation completes; the `state` event reports when
media is connected. `remoteAudio` excludes the local participant and listen-only
members. `participants` includes identities, slots, roles, and mute states. Handle
autoplay permission in your UI. `leave()` stops captured microphone tracks and
closes signaling and WebRTC, including when called during a pending join.
Media disconnection ends the session; reconnect manually for now.

To change the SDK: `npm ci`, edit `sdk/src/index.ts`, then `npm run build:sdk`.
`npm run typecheck` checks its TypeScript API. The current protocol uses five
ordered audio transceivers; old single-track relay clients must update.

## Checks

```sh
mix format --check-formatted
mix test
```

The optional browser test uses isolated Chromium contexts with synthetic
microphone audio. With the server running in another terminal:

```sh
npm ci
npm run test:browser
```

Set `CHROMIUM_PATH` if Chromium is not at `/usr/bin/chromium`. This checks actual
received RTP and decoded audio energy in every direction for three/four participants,
playback, mute, duplicate identities, fifth-participant rejection, slot reuse,
leave/rejoin, tab-close cleanup, role restrictions, and room isolation. Node is
needed only for SDK development and browser tests, not to run the app.

## Access and resource limits

All WebSocket connections require a signed access token. A grant contains a room,
participant identity, and role (`participant`, `publisher`, or `listener`). The signature and
five-minute lifetime are checked on connect and again on room join. Expiry limits
admission, not the duration of an established call. Tokens are bearer credentials
and can be reused within that window; they are not single-use or revocable yet.
An identity can have only one active session in a room. `participant` can publish
and subscribe; `publisher` can only publish; `listener` can only subscribe.

These are Phoenix signed tokens, **not JWTs or LiveKit-compatible tokens**. Issue
them from trusted Elixir application code after authenticating your own users:

```elixir
{:ok, token} = WebRTCLive.Access.issue("demo", "alice", "participant")
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
- Four participants per room, with one microphone and up to three remote speakers each.
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
and `PUBLIC_IP` are required, with HTTPS terminated at a reverse proxy. `PORT`
defaults to 4000, bound to loopback. Production ICE uses UDP 50000–50100 and
advertises only `PUBLIC_IP`. See the deployment guide for Linux host networking.

## Scope and next steps

This is an experimental milestone, **not ready for unrestricted public use**.
See [Droplet deployment](deploy/README.md) for the limited-access HTTPS setup.
Signed admission and application resource limits are implemented. User account
authentication, token revocation, per-account quotas, HTTP/connection rate limiting,
and cross-network TURN testing remain. Rooms and calls are lost on restart.
It does not implement video, automatic reconnect,
recording, simulcast, congestion adaptation, or the LiveKit SDK protocol.

Next: video, TURN verification across networks, and deployment hardening.
