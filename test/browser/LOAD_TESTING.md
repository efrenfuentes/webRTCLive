# Audio load tests

Run from the checkout with npm dependencies and Chromium installed. Uses real
WebRTC connections to the deployed SFU, synthetic microphones, and three audio
decoders per participant. Four unique identities are created per room. All
clients run in one browser page to reduce load-generator UI overhead; this is
not a simulation of independent devices or diverse networks.

```sh
BASE_URL=https://webrtc.efrenfuentes.net DEPLOY_SSH_HOST=codex-keen-dusk-76f6 ROOMS=5 DURATION_SECONDS=60 REPORT_PATH=/tmp/load.json node test/browser/load.mjs
```

Default mode disables ICE servers to test direct media. Add `TURN_TRANSPORT=udp`
or `TURN_TRANSPORT=tcp` to force relay-only ICE and verify the selected transport.
The JSON report contains no admission tokens or TURN credentials. It records
connection/stream counts, sampled Docker CPU/memory, receive packet loss, jitter,
RTT, audio concealment, aggregate received RTP payload Mbps, and generator CPU/RAM.
Host-network Docker NetIO is not useful here, so use received RTP stats instead;
these exclude headers, signaling and TURN overhead and are not billable traffic.

The test ramps participants sequentially, waits five seconds, then samples each
ten seconds plus SSH/monitoring overhead. DURATION_SECONDS specifies nominal
sampling time; actual measured time is longer and appears in elapsedSeconds.
CPU is sampled rather than continuous peak monitoring. Join times include
microphone acquisition and signaling. Each interval must have increasing
decoded audio energy on all expected streams. Three consecutive samples above
90% server/container CPU, 90% generator CPU, or 5% packet loss stop the test;
low generator free memory or missing streams also stop it. These broad safety
checks are not a production voice-quality SLO. Browser cleanup runs on failure.

## Temporary expanded test

Do not increase production caps permanently from a short test. With no real
calls active, upload `deploy/load-test.compose.yaml` to the same path under
`/opt/webrtc-live`, then run:

```sh
BASE_URL=https://webrtc.efrenfuentes.net DEPLOY_SSH_HOST=codex-keen-dusk-76f6 DURATION_SECONDS=60 REPORT_PATH=/tmp/load-10.json sh test/browser/load-expanded.sh
```

This restarts the app with ten rooms/40 sessions, runs direct-media testing,
then restores ordinary Compose settings in an exit trap. Verify restoration
after interruption or SSH failure with `docker compose up -d app` on the server.
TURN allocation quotas are not raised. Both restarts disconnect active calls.
Long soak tests, join storms, real speech/listening checks, client churn,
network impairment, diverse clients and multi-location generators are separate
follow-ups; short synthetic tests do not establish a guaranteed maximum.
