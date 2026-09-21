# Initial deployed audio load results — 2026-09-21 UTC

Tested deployment: `d6748ac`, `webrtc.efrenfuentes.net`, DigitalOcean NYC3,
1 shared vCPU / 2 GB RAM ($12/month base plan). Tests ran 01:49–02:04 UTC.
No instance resize, paid service, or permanent capacity change was made.

## Outcome

Keep the current **5 rooms / 20 participants** admission cap. Five four-person
rooms completed short tests with direct audio, forced TURN/UDP, and forced
TURN/TCP. Every participant transmitted synthetic audio and decoded the other
three participants throughout every measured interval (60 receiving streams).
These are initial results, not a guaranteed production capacity or voice-quality SLO.

| Rooms / clients | Path | Result | Mean / max sampled container CPU | Peak app RAM | Aggregate receive packet loss |
| --- | --- | --- | --- | --- | --- |
| 1 / 4 | Direct | Pass | 14.5% / 21.8% | 138.7 MiB | 0.024% |
| 5 / 20 | Direct | Pass | 41.5% / 43.8% | 200.8 MiB | 0.153% |
| 5 / 20 | TURN/UDP | Pass | 55.1% / 59.1% | 196.6 MiB | 0.004% |
| 5 / 20 | TURN/TCP | Pass | 62.1% / 71.9% | 202.0 MiB | 0.000% |
| 10 / 40 | Direct | Safety stop | 89.7% / 93.0% | 322.1 MiB | 0.030% |

CPU is the sum of app, coturn, and Caddy Docker samples, not complete host CPU.
100% represents one core. A separate ten-room ramp snapshot reached 100.48%
app CPU. Successful stages used six samples with ten-second waits plus SSH
overhead: approximately 82–84 seconds of steady measurement at five rooms,
plus ramp and warmup. The one-room report has nominal rather than wall-clock
sample offsets. Each complete run took roughly 100–130 seconds including setup.

Five-room results:

- Direct: max sampled jitter 18 ms; max ICE RTT 179 ms; audio concealment 0.776%.
- TURN/UDP: max jitter 10 ms; max RTT 156 ms; concealment 0.703%.
- TURN/TCP: max jitter 15 ms; max RTT 174 ms; concealment 0.565%.
- Aggregate received RTP payload: approximately 1.4–1.5 Mbps, excluding headers,
  signaling and relay overhead. This is not a billable-bandwidth estimate.
- Slowest individual join: 3.02 s direct, 1.60 s TURN/UDP, 2.42 s TURN/TCP.
- Generator sampled CPU peaked at 53–56% in the five-room stages.

Zero TCP packet loss does not mean no audible impairment: transport retransmits
and late playout can still cause concealment. No human listening assessment was
performed. Short tests can miss intermittent degradation.

## Why not raise the cap?

All 40 clients connected at ten rooms, and all 120 incoming streams continued
decoding during the 44.61-second measured window. However, server CPU sampled
84–93%, the local generator reached 94.2% CPU, and one sampled ICE RTT reached
1.828 seconds. The safety stop fired after three consecutive intervals with
either server or generator CPU above 90%. It was not a connection failure.

Both ends were under pressure, so this does **not** establish the SFU's maximum
capacity or attribute all delay to the Droplet. Twenty rooms were not attempted.
The generator was this four-core Linux desktop, using one Chromium page with
independent SDK Room/PeerConnection instances and synthetic microphones. All
clients shared one machine/network; this is not a diverse-device/network test.
Load was ramped sequentially, not as a join storm, and no long soak was run.

An earlier TURN/TCP attempt reused four identities across five rooms and timed
out joining the fifth room. This conflicts with the four-allocation-per-user
TURN quota, so that run was excluded from capacity conclusions. A repeat with
20 unique identities succeeded without changing coturn limits.

## Restoration and follow-ups

The ten-room override was removed from the running Compose configuration by
the test wrapper. The production cap is restored to five rooms / twenty
sessions. Test browsers close their connections on completion or failure.

Before increasing capacity: use a dedicated/multi-host generator, run a 30–60
minute five-room soak, test client churn and reconnects, and measure real voice
quality on varied networks. See [reproduction instructions](LOAD_TESTING.md).
Test tooling and this report are not automatically deployed or committed.

Raw JSON reports are on the local machine (no tokens or TURN secrets):

- `/tmp/webrtc-load-1-direct.json`
- `/tmp/webrtc-load-5-direct.json`
- `/tmp/webrtc-load-5-udp.json`
- `/tmp/webrtc-load-5-tcp-unique.json`
- `/tmp/webrtc-load-10-direct.json`
- `/tmp/webrtc-load-5-tcp.json` (excluded initial identity-reuse attempt)
