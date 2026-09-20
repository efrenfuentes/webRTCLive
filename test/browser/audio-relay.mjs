import assert from "node:assert/strict";
import { chromium } from "playwright";

// Run against `mix phx.server`. Fake microphone input avoids accessing real devices.
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || "/usr/bin/chromium",
  headless: true,
  args: ["--use-fake-device-for-media-stream", "--use-fake-ui-for-media-stream", "--autoplay-policy=no-user-gesture-required"],
});
const errors = [];
const baseURL = process.env.BASE_URL || "http://localhost:4000";

async function page(role, room) {
  const context = await browser.newContext({ permissions: ["microphone"] });
  // Capture connections only in the test; the public client exposes no debug globals.
  await context.addInitScript(() => {
    const Native = window.RTCPeerConnection;
    window.testPeers = [];
    window.RTCPeerConnection = class extends Native {
      constructor(...args) { super(...args); window.testPeers.push(this); }
    };
  });
  const page = await context.newPage();
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(baseURL);
  await page.locator("#role").selectOption(role);
  await page.locator("#room").fill(room);
  return page;
}

async function join(page) {
  await page.locator("#join").click();
  await page.waitForFunction(() => window.testPeers.at(-1)?.connectionState === "connected", null, { timeout: 15000 });
}

async function audioReceived(page) {
  await page.waitForFunction(async () => {
    const pc = window.testPeers.at(-1);
    if (!pc) return false;
    const stats = [...(await pc.getStats()).values()];
    return stats.some((s) => s.type === "inbound-rtp" && s.kind === "audio" && s.packetsReceived > 20 && s.totalAudioEnergy > 0);
  }, null, { timeout: 15000 });
  assert.equal(await page.locator("#remote").evaluate((audio) => audio.paused), false);
}

try {
  const room = `browser-${Date.now()}`;
  const publisher = await page("publisher", room);
  const listener = await page("listener", room);
  assert.equal((await listener.request.get(`${baseURL}/config`)).status(), 401);
  const denied = await page("listener", room);
  const grant = await denied.request.post(`${baseURL}/dev/token`, {
    data: { room, identity: "wrong-role", role: "publisher" },
  });
  assert.equal(grant.status(), 200);
  await denied.locator("#token").fill((await grant.json()).token);
  await denied.locator("#join").click();
  await denied.waitForFunction(() => document.querySelector("#status").textContent.includes("unauthorized"));
  await denied.close();
  console.log("PASS: ICE config protected and token role enforced in the browser.");
  await join(listener); // Listener-first admission must work.
  await join(publisher);
  await audioReceived(listener);
  console.log("PASS: Opus audio crosses two browser/server WebRTC connections and plays.");

  const duplicate = await page("publisher", room);
  await duplicate.locator("#join").click();
  await duplicate.waitForFunction(() => document.querySelector("#status").textContent.includes("role_taken"));
  console.log("PASS: duplicate publisher rejected.");

  await publisher.locator("#mute").click();
  assert.equal(await publisher.evaluate(() => window.testPeers.at(-1).getSenders()[0].track.enabled), false);
  await publisher.locator("#mute").click();
  assert.equal(await publisher.evaluate(() => window.testPeers.at(-1).getSenders()[0].track.enabled), true);

  await listener.locator("#leave").click();
  await join(listener);
  await audioReceived(listener);
  console.log("PASS: mute/unmute and listener leave/rejoin.");

  await publisher.locator("#leave").click();
  await listener.waitForFunction(() => document.querySelector("#join").disabled === false);
  assert.equal(await publisher.evaluate(() => window.testPeers.at(-1).connectionState), "closed");
  await join(publisher); // Publisher-first admission after room cleanup.
  await join(listener);
  await audioReceived(listener);
  await publisher.close(); // Abrupt tab closure must clean up too.
  await listener.waitForFunction(() => document.querySelector("#join").disabled === false);
  assert.deepEqual(errors, []);
  console.log("PASS: publisher departure, fresh room, tab-close cleanup; no browser errors.");
} finally {
  await browser.close();
}
