import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { setTimeout } from "node:timers/promises";
import { chromium } from "playwright";

const baseURL = process.env.BASE_URL;
const sshHost = process.env.DEPLOY_SSH_HOST;
assert.ok(baseURL?.startsWith("https://"), "Set BASE_URL to the deployed HTTPS origin");
assert.match(sshHost || "", /^[a-zA-Z0-9][a-zA-Z0-9_.-]*$/, "Set DEPLOY_SSH_HOST");
const room = `smoke-${Date.now()}`;
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || "/usr/bin/chromium",
  headless: true,
  args: ["--use-fake-device-for-media-stream", "--use-fake-ui-for-media-stream", "--autoplay-policy=no-user-gesture-required"],
});

try {
  const pages = [];
  for (const identity of ["alice", "bob"]) {
    const token = execFileSync("ssh", [sshHost,
      `cd /opt/webrtc-live && docker compose exec -T app bin/webrtc_live rpc 'WebRTCLive.Access.issue("${room}", "${identity}", "participant") |> elem(1) |> IO.puts()'`,
    ], { encoding: "utf8", timeout: 30000 }).trim();
    const context = await browser.newContext({ permissions: ["microphone"] });
    await context.addInitScript(() => {
      const Native = window.RTCPeerConnection;
      window.RTCPeerConnection = class extends Native {
        constructor(...args) { super(...args); window.smokePeer = this; }
      };
    });
    const page = await context.newPage();
    await page.goto(baseURL);
    assert.equal((await page.request.get(`${baseURL}/health`)).status(), 200);
    assert.equal((await page.request.post(`${baseURL}/dev/token`, { data: {} })).status(), 404);
    assert.equal((await page.request.get(`${baseURL}/config`)).status(), 401);
    await page.locator("#room").fill(room);
    await page.locator("#role").selectOption("participant");
    await page.locator("#token").fill(token);
    await page.locator("#join").click();
    await page.waitForFunction(() => window.smokePeer?.connectionState === "connected", null, { timeout: 30000 });
    pages.push(page);
  }
  for (const page of pages) {
    let decoded = false;
    const deadline = Date.now() + 20000;
    while (Date.now() < deadline) {
      decoded = await page.evaluate(async () => [...(await window.smokePeer.getStats()).values()]
        .some(s => s.type === "inbound-rtp" && s.kind === "audio" && s.packetsReceived > 10 && s.totalAudioEnergy > 0));
      if (decoded) break;
      await setTimeout(200);
    }
    assert.ok(decoded, "Each client must receive and decode remote audio");
  }
  console.log("PASS: trusted HTTPS, protected endpoints, and two-way decoded audio through the deployed server.");
} finally {
  await browser.close();
}
