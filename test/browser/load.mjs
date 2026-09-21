import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { setTimeout } from "node:timers/promises";
import { cpus, freemem, loadavg } from "node:os";
import { writeFile } from "node:fs/promises";
import { chromium } from "playwright";

const exec = promisify(execFile);
const baseURL = process.env.BASE_URL;
const host = process.env.DEPLOY_SSH_HOST;
const rooms = Number(process.env.ROOMS || 1);
const duration = Number(process.env.DURATION_SECONDS || 60);
const transport = process.env.TURN_TRANSPORT || "direct";
assert.ok(baseURL?.startsWith("https://"));
assert.match(host || "", /^[a-zA-Z0-9][a-zA-Z0-9_.-]*$/);
assert.ok(Number.isInteger(rooms) && rooms >= 1 && rooms <= 20);
assert.ok(duration >= 30 && duration <= 600);
assert.ok(["direct", "udp", "tcp"].includes(transport));
const run = `load-${Date.now()}`;
const ssh = async command => (await exec("ssh", [host, command], { timeout: 30000, maxBuffer: 1024 * 1024 })).stdout;
const rpc = expression => ssh(`cd /opt/webrtc-live && docker compose exec -T app bin/webrtc_live rpc '${expression}'`);
const grants = JSON.parse((await rpc(`for r <- 1..${rooms}, p <- 1..4 do {:ok, token} = WebRTCLive.Access.issue("${run}-#{r}", "r#{r}p#{p}", "participant"); %{room: "${run}-#{r}", identity: "r#{r}p#{p}", token: token} end |> Jason.encode!() |> IO.puts()`)).trim());
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || "/usr/bin/chromium", headless: true,
  args: ["--use-fake-device-for-media-stream", "--use-fake-ui-for-media-stream", "--autoplay-policy=no-user-gesture-required", "--disable-background-timer-throttling"] });
const report = { run, rooms, clients: grants.length, transport, durationSeconds: duration, started: new Date().toISOString(), samples: [], errors: [] };
const cpuTime = () => cpus().reduce((a, c) => ({idle: a.idle + c.times.idle, total: a.total + Object.values(c.times).reduce((x,y) => x+y,0)}), {idle:0,total:0});
let priorCPU = cpuTime();
try {
  const context = await browser.newContext({ permissions: ["microphone"] });
  const page = await context.newPage();
  page.on("pageerror", error => report.errors.push(error.message));
  page.on("console", message => {
    if (message.text().startsWith("LOAD ")) console.log(message.text());
  });
  await page.goto(new URL("/index.html", baseURL).href);
  await page.evaluate(async ({grants, transport}) => {
    const {Room} = await import("/sdk.js");
    const Native = window.RTCPeerConnection;
    window.loadPeers = [];
    window.loadRooms = [];
    window.joinTimes = [];
    window.RTCPeerConnection = class extends Native {
      constructor(config) {
        if (transport === "direct") config.iceServers = [];
        else {
          config.iceTransportPolicy = "relay";
          config.iceServers = config.iceServers.map(s => ({...s, urls: (Array.isArray(s.urls) ? s.urls : [s.urls]).filter(u => u.endsWith(`transport=${transport}`))})).filter(s => s.urls.length);
        }
        super(config); window.loadPeers.push(this);
      }
    };
    // Ramp one room at a time; this measures sustained media, not a join storm.
    for (const grant of grants) {
      const client = new Room();
      window.loadRooms.push(client);
      const audios = new Map();
      client.on("tracks", () => {
        for (const {track} of client.remoteAudio) {
          if (audios.has(track.id)) continue;
          const audio = document.createElement("audio");
          audio.autoplay = true; audio.srcObject = new MediaStream([track]);
          document.body.append(audio); audios.set(track.id, audio);
          audio.play().catch(() => {});
        }
      });
      const started = performance.now();
      await client.join({room: grant.room, token: grant.token, role: "participant"});
      const pc = window.loadPeers.at(-1);
      await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error(`Connection timeout: ${grant.room}/${grant.identity}`)), 30000);
        const check = () => { if (pc.connectionState === "connected") {clearTimeout(timer); resolve();} };
        pc.addEventListener("connectionstatechange", check); check();
      });
      window.joinTimes.push(performance.now() - started);
      if (window.joinTimes.length % 4 === 0) console.log(`LOAD connected ${window.joinTimes.length} clients`);
    }
  }, {grants, transport});
  console.log(`Connected ${grants.length} clients in ${rooms} rooms (${transport}); warming up 5 seconds.`);
  await setTimeout(5000);
  const stats = () => page.evaluate(async () => Promise.all(window.loadPeers.map(async pc => {
    const stats = await pc.getStats();
    const entries = [...stats.values()];
    const t = entries.find(s => s.type === "transport" && s.selectedCandidatePairId);
    const pair = stats.get(t?.selectedCandidatePairId);
    const candidate = stats.get(pair?.localCandidateId);
    return {state: pc.connectionState, candidate: candidate?.candidateType, relayProtocol: candidate?.relayProtocol,
      rtt: pair?.currentRoundTripTime || 0,
      streams: entries.filter(s => s.type === "inbound-rtp" && s.kind === "audio").map(s => ({id:s.id, packets:s.packetsReceived || 0, lost:s.packetsLost || 0, bytes:s.bytesReceived || 0, energy:s.totalAudioEnergy || 0, jitter:s.jitter || 0, concealed:s.concealedSamples || 0, samples:s.totalSamplesReceived || 0}))};
  })));
  let previous = await stats();
  const measurementStarted = Date.now();
  let previousSampleTime = measurementStarted;
  report.joinMs = await page.evaluate(() => window.joinTimes);
  let hot = 0;
  for (let elapsed = 0; elapsed < duration; elapsed += 10) {
    await setTimeout(10000);
    const current = await stats();
    const sampleTime = Date.now();
    const containers = (await ssh('docker stats --no-stream --format "{{json .}}"')).trim().split("\n").map(JSON.parse);
    const cpu = cpuTime();
    const sample = {elapsedSeconds: (sampleTime-measurementStarted)/1000, connected: current.filter(s => s.state === "connected").length,
      activeStreams: 0, expectedStreams: grants.length*3, received:0,lost:0,concealed:0,totalSamples:0,receivedBytes:0,
      maxJitterMs:0,maxRttMs:0,containers, generatorCpuPercent:100*(1-(cpu.idle-priorCPU.idle)/(cpu.total-priorCPU.total)),generatorFreeMB:freemem()/1048576,generatorLoad:loadavg()[0]};
    priorCPU = cpu;
    current.forEach((peer,i) => {
      assert.equal(peer.state, "connected");
      if (transport !== "direct") {assert.equal(peer.candidate,"relay"); assert.equal(peer.relayProtocol,transport);}
      else assert.notEqual(peer.candidate,"relay");
      sample.maxRttMs = Math.max(sample.maxRttMs,peer.rtt*1000);
      for (const stream of peer.streams) {
        const old = previous[i].streams.find(s => s.id === stream.id);
        if (!old) continue;
        if (stream.packets > old.packets && stream.energy > old.energy) sample.activeStreams++;
        sample.received += stream.packets-old.packets;
        sample.receivedBytes += stream.bytes-old.bytes;
        sample.lost += stream.lost-old.lost;
        sample.concealed += stream.concealed-old.concealed;
        sample.totalSamples += stream.samples-old.samples;
        sample.maxJitterMs = Math.max(sample.maxJitterMs,stream.jitter*1000);
      }
    });
    sample.lossPercent = 100*Math.max(0,sample.lost)/Math.max(1,sample.received+sample.lost);
    sample.concealmentPercent = 100*sample.concealed/Math.max(1,sample.totalSamples);
    sample.receivedMbps = sample.receivedBytes*8/((sampleTime-previousSampleTime)/1000)/1e6;
    previousSampleTime = sampleTime;
    report.samples.push(sample); previous = current;
    console.log(JSON.stringify(sample));
    assert.equal(sample.activeStreams,sample.expectedStreams,"All remote streams must continue decoding");
    const serverCPU = containers.reduce((a,c) => a + parseFloat(c.CPUPerc),0);
    hot = serverCPU > 90 || sample.generatorCpuPercent > 90 || sample.lossPercent > 5 ? hot+1 : 0;
    assert.ok(sample.generatorFreeMB > 350,"Stop: generator memory is low");
    assert.ok(hot < 3,"Stop: sustained server/generator saturation or packet loss");
  }
  report.passed = true;
} catch(error) {
  report.passed = false; report.errors.push(error.message); process.exitCode = 1;
} finally {
  await browser.close();
  report.finished = new Date().toISOString();
  const path = process.env.REPORT_PATH || `/tmp/${run}.json`;
  await writeFile(path, JSON.stringify(report,null,2));
  console.log(`RESULT ${report.passed ? "PASS" : "FAIL"}: ${path}`);
  if (report.errors.length) console.error(report.errors.join("\n"));
}
