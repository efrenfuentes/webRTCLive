import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { chromium } from "playwright";

const baseURL = process.env.BASE_URL || "http://localhost:4000";
const sshHost = process.env.DEPLOY_SSH_HOST;
if (sshHost) assert.match(sshHost, /^[a-zA-Z0-9][a-zA-Z0-9_.-]*$/);
const slug = `auth-smoke-${Date.now()}`;
function rpc(code) {
  if (sshHost) {
    assert.ok(!code.includes("'"));
    return execFileSync("ssh", [sshHost, `cd /opt/webrtc-live && docker compose exec -T app bin/webrtc_live rpc '${code}'`], { encoding: "utf8", timeout: 30000 });
  }
  return execFileSync("mix", ["run", "--no-start", "-e", `Application.ensure_all_started(:postgrex); Application.ensure_all_started(:ecto_sql); {:ok, _} = WebRTCLive.Repo.start_link(); ${code}`], { encoding: "utf8", timeout: 60000 });
}

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || "/usr/bin/chromium", headless: true,
  args: ["--use-fake-device-for-media-stream", "--use-fake-ui-for-media-stream", "--autoplay-policy=no-user-gesture-required"] });
try {
  const output = rpc(`
    alias WebRTCLive.{Accounts, Calls, Repo}
    {:ok, alice} = Accounts.register_user(%{email: "${slug}-alice@example.invalid"})
    {:ok, bob} = Accounts.register_user(%{email: "${slug}-bob@example.invalid"})
    {:ok, _} = Calls.create(alice, "${slug}")
    {:ok, _} = Calls.invite(alice, "${slug}", bob.email, "participant")
    tokens = Enum.map([alice, bob], fn user ->
      {encoded, stored} = Accounts.UserToken.build_email_token(user, "login")
      Repo.insert!(stored)
      encoded
    end)
    IO.puts("AUTH_RESULT=" <> Jason.encode!(tokens))
  `);
  const tokens = JSON.parse(output.split("AUTH_RESULT=")[1].trim());
  const pages = [];
  for (const token of tokens) {
    const context = await browser.newContext({ permissions: ["microphone"] });
    await context.addInitScript(() => {
      const Native = window.RTCPeerConnection;
      window.RTCPeerConnection = class extends Native {
        constructor(config) { super(config); window.smokePeer = this; }
      };
    });
    const page = await context.newPage();
    const browserErrors = [];
    page.on("pageerror", error => browserErrors.push(error.message));
    page.on("console", message => { if (message.type() === "error") browserErrors.push(message.text()); });
    await page.goto(`${baseURL}/users/log-in/${token}`);
    await page.getByRole("button", { name: "Confirm and stay logged in", exact: true }).click();
    await page.waitForURL(`${baseURL}/`);
    const session = (await context.cookies()).find(cookie => cookie.name === "_webrtc_live_session");
    assert.ok(session?.httpOnly);
    assert.equal(session.sameSite, "Lax");
    if (baseURL.startsWith("https://")) assert.ok(session.secure);
    await page.getByRole("link", { name: slug, exact: true }).click();
    await page.locator("#join").click();
    try {
      await page.waitForFunction(() => window.smokePeer?.connectionState === "connected", null, { timeout: 30000 });
    } catch {
      throw new Error(`Authenticated call failed: ${await page.locator("#status").textContent()}; ${browserErrors.join("; ")}`);
    }
    pages.push(page);
  }
  for (const page of pages) {
    await page.waitForFunction(async () => [...(await window.smokePeer.getStats()).values()]
      .some(s => s.type === "inbound-rtp" && s.kind === "audio" && s.packetsReceived > 10 && s.totalAudioEnergy > 0), null, { timeout: 30000 });
    const missingCSRF = await page.request.post(`${baseURL}/rooms/${slug}/join`);
    assert.equal(missingCSRF.status(), 403);
  }
  assert.equal(await pages[1].getByRole("link", { name: "Delete room", exact: true }).count(), 0);
  const manage = await pages[0].context().newPage();
  await manage.goto(`${baseURL}/rooms/${slug}/delete`);
  await manage.getByRole("button", { name: "Permanently delete room", exact: true }).click();
  await manage.waitForURL(`${baseURL}/rooms/${slug}`);
  assert.match(await manage.getByRole("alert").textContent(), /room is active/);
  await manage.goto(baseURL);
  assert.equal(await manage.evaluate(() => getComputedStyle(document.documentElement).backgroundColor), "rgb(16, 22, 25)");
  await manage.locator("#slug").fill(`${slug}-delete`);
  await manage.getByRole("button", { name: "Create room", exact: true }).click();
  await manage.waitForURL(`${baseURL}/rooms/${slug}-delete`);
  await manage.getByRole("link", { name: "Delete room", exact: true }).click();
  await manage.getByRole("link", { name: "Cancel", exact: true }).click();
  await manage.waitForURL(`${baseURL}/rooms/${slug}-delete`);
  await manage.setViewportSize({ width: 375, height: 812 });
  assert.ok(await manage.evaluate(() => document.documentElement.scrollWidth <= innerWidth), "Room layout must fit mobile screens");
  if (process.env.SCREENSHOT_PATH) await manage.screenshot({ path: process.env.SCREENSHOT_PATH, fullPage: true });
  await manage.getByRole("link", { name: "Delete room", exact: true }).click();
  await manage.getByRole("button", { name: "Permanently delete room", exact: true }).click();
  await manage.waitForURL(`${baseURL}/`);
  assert.equal(await manage.getByRole("link", { name: `${slug}-delete`, exact: true }).count(), 0);
  assert.equal((await manage.request.get(`${baseURL}/rooms/${slug}-delete`)).status(), 404);
  await manage.close();
  await pages[0].getByRole("button", { name: "Log out", exact: true }).click();
  await pages[0].waitForURL(`${baseURL}/users/log-in`);
  await pages[1].waitForFunction(() => document.querySelector("#members").textContent.includes("1 / 4"));
  console.log("PASS: two magic-link logins, automatic room grants, bidirectional decoded audio, CSRF enforcement, and logout cleanup.");
  console.log("PASS: original dark theme, mobile layout, owner-only confirmed deletion, cancellation, and active-room protection.");
} finally {
  await browser.close();
  rpc(`
    import Ecto.Query
    alias WebRTCLive.{Repo, Calls, Accounts}
    Repo.delete_all(from r in Calls.Room, where: r.slug in ["${slug}", "${slug}-delete"])
    Repo.delete_all(from u in Accounts.User, where: u.email in ["${slug}-alice@example.invalid", "${slug}-bob@example.invalid"])
    IO.puts("Test accounts removed")
  `);
}
