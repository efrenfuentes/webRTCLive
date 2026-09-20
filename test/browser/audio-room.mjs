import assert from "node:assert/strict";
import { chromium } from "playwright";
import { setTimeout } from "node:timers/promises";

const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || "/usr/bin/chromium",
  headless: true,
  args: ["--use-fake-device-for-media-stream", "--use-fake-ui-for-media-stream", "--autoplay-policy=no-user-gesture-required"],
});
const errors = [];
const baseURL = process.env.BASE_URL || "http://localhost:4000";

async function page(identity, room, role = "participant") {
  const context = await browser.newContext({ permissions: ["microphone"] });
  await context.addInitScript(() => {
    const Native = window.RTCPeerConnection;
    window.testPeers = [];
    window.RTCPeerConnection = class extends Native {
      constructor(...args) {
        super(...args); window.testPeers.push(this);
        this.addEventListener("track", (event) => { window.testTrackEvents = [...(window.testTrackEvents || []), { mid: event.transceiver.mid, index: this.getTransceivers().indexOf(event.transceiver) }]; });
      }
    };
  });
  const page = await context.newPage();
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(baseURL);
  await page.locator("#identity").fill(identity);
  await page.locator("#room").fill(room);
  await page.locator("#role").selectOption(role);
  return page;
}

async function join(page) {
  await page.locator("#join").click();
  await page.waitForFunction(() => window.testPeers.at(-1)?.connectionState === "connected", null, { timeout: 15000 });
}

async function roster(page, count) {
  await page.waitForFunction((n) => document.querySelectorAll("#participants section").length === n, count);
}

async function energy(page) {
  return page.evaluate(async () => {
    const entries = [...(await window.testPeers.at(-1).getStats()).values()];
    return Object.fromEntries(entries.filter((s) => s.type === "inbound-rtp" && s.kind === "audio")
      .map((s) => [s.trackIdentifier, s.totalAudioEnergy || 0]));
  });
}

async function hear(page, identities, before = {}) {
  const deadline = Date.now() + 20000;
  while (Date.now() < deadline) {
    const ready = await page.evaluate(async ({ identities, before }) => {
      const stats = [...(await window.testPeers.at(-1).getStats()).values()];
      return identities.every((identity) => {
        const audio = [...document.querySelectorAll("#participants section")]
          .find((row) => row.dataset.identity === identity)?.querySelector("audio");
        const id = audio?.srcObject?.getAudioTracks()[0]?.id;
        return audio && !audio.paused && stats.some((s) => s.type === "inbound-rtp" &&
          s.trackIdentifier === id && s.packetsReceived > 10 && s.totalAudioEnergy > (before[id] || 0));
      });
    }, { identities, before });
    if (ready) return;
    await setTimeout(100);
  }
  throw new Error(JSON.stringify(await page.evaluate(() => ({
    status: document.querySelector("#status").textContent,
    events: window.testTrackEvents,
    receivers: window.testPeers.at(-1).getTransceivers().map((t) => ({ mid: t.mid, direction: t.currentDirection })),
    roster: document.querySelector("#participants").innerHTML,
  }))));
}

try {
  const name = `conference-${Date.now()}`;
  const alice = await page("alice", name);
  const bob = await page("bob", name);
  const carol = await page("carol", name);
  for (const member of [alice, bob, carol]) await join(member);
  await Promise.all([hear(alice, ["bob", "carol"]), hear(bob, ["alice", "carol"]), hear(carol, ["alice", "bob"])]);
  for (const member of [alice, bob, carol]) assert.equal(await member.locator("#participants audio").count(), 2,
    JSON.stringify({ status: await member.locator("#status").textContent(), roster: await member.locator("#participants").textContent(), errors }));
  console.log("PASS: three participants simultaneously send, receive, and decode each other's audio without self playback.");

  const duplicate = await page("alice", name);
  await duplicate.locator("#join").click();
  await duplicate.waitForFunction(() => document.querySelector("#status").textContent.includes("identity_taken"));
  await duplicate.close();
  await bob.locator("#mute").click();
  await alice.waitForFunction(() => document.querySelector('[data-identity="bob"] small').textContent.includes("muted"));
  assert.equal(await bob.evaluate(() => window.testPeers.at(-1).getSenders()[0].track.enabled), false);
  await bob.locator("#mute").click();
  const beforeUnmute = await energy(alice);
  await hear(alice, ["bob", "carol"], beforeUnmute);
  console.log("PASS: duplicate identities rejected and mute/unmute synchronizes across the room.");

  const dave = await page("dave", name);
  await join(dave);
  await Promise.all([hear(dave, ["alice", "bob", "carol"]), hear(alice, ["bob", "carol", "dave"]), hear(bob, ["alice", "carol", "dave"]), hear(carol, ["alice", "bob", "dave"])]);
  const eve = await page("eve", name);
  await eve.locator("#join").click();
  await eve.waitForFunction(() => document.querySelector("#status").textContent.includes("room_full"));
  console.log("PASS: four-way audio works and the fifth participant is rejected.");

  const alicePeerCount = await alice.evaluate(() => window.testPeers.length);
  await bob.locator("#leave").click();
  await roster(alice, 3);
  const beforeReuse = await energy(alice);
  await join(eve);
  await hear(alice, ["carol", "dave", "eve"], beforeReuse);
  assert.equal(await alice.evaluate(() => window.testPeers.length), alicePeerCount);
  assert.equal(await alice.locator('[data-identity="bob"]').count(), 0);
  await eve.close();
  await roster(alice, 3);
  const beforeRejoin = await energy(alice);
  await join(bob);
  await hear(alice, ["bob", "carol", "dave"], beforeRejoin);
  await hear(bob, ["alice", "carol", "dave"]);
  console.log("PASS: slot replacement, tab-close cleanup, and rejoin preserve existing calls and decoded audio.");

  // A separate room must not hear the conference; listen-only needs no microphone.
  const listener = await page("observer", `${name}-isolated`, "listener");
  await join(listener);
  await roster(listener, 1);
  assert.equal(await listener.locator("#participants audio").count(), 0);
  assert.equal(await listener.evaluate(() => window.testPeers.at(-1).getSenders().some((s) => s.track)), false);
  const publisher = await page("speaker", `${name}-isolated`, "publisher");
  await join(publisher);
  await hear(listener, ["speaker"]);
  assert.equal(await publisher.locator("#participants audio").count(), 0);
  assert.equal((await listener.request.get(`${baseURL}/config`)).status(), 401);
  const cancelled = await page("cancelled", `${name}-cancelled`);
  const grant = await cancelled.request.post(`${baseURL}/dev/token`, {
    data: { room: `${name}-cancelled`, identity: "cancelled", role: "participant" },
  });
  const cancellation = await cancelled.evaluate(async ({ token, name }) => {
    const { Room } = await import("/sdk.js");
    const room = new Room();
    const original = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
    let release;
    let signal;
    const requested = new Promise((resolve) => { signal = resolve; });
    const gate = new Promise((resolve) => { release = resolve; });
    let captured;
    navigator.mediaDevices.getUserMedia = async (constraints) => {
      captured = await original(constraints);
      signal();
      await gate;
      return captured;
    };
    const joining = room.join({ room: `${name}-cancelled`, token }).catch((error) => error.message);
    await requested;
    room.leave();
    release();
    const result = await joining;
    navigator.mediaDevices.getUserMedia = original;
    return { result, stopped: captured.getTracks().every((track) => track.readyState === "ended"), peers: window.testPeers.length };
  }, { token: (await grant.json()).token, name });
  assert.deepEqual(cancellation, { result: "Join cancelled", stopped: true, peers: 0 });
  assert.deepEqual(errors, []);
  console.log("PASS: room isolation, publish/listen permissions, protected config, pending-join cleanup, and no browser errors.");
} finally {
  await browser.close();
}
