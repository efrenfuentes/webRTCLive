import { Room } from "/sdk.js";

const $ = (id) => document.getElementById(id);
const room = new Room();
let attempt = null;
let muted = false;
const authenticated = $("join-form").dataset.authenticated === "true";
if (!authenticated) $("identity").value = `guest-${crypto.randomUUID().slice(0, 8)}`;

function controls(joined) {
  for (const id of ["join", "room", "identity", "role", "token"]) $(id).disabled = joined;
  $("leave").disabled = !joined;
  $("mute").disabled = !joined || $("role").value === "listener";
}

function render() {
  $("members").textContent = room.participants.length ? `${room.participants.length} / 4 participants` : "Room is not connected.";
  const roster = $("participants");
  const identities = new Set(room.participants.map((p) => p.identity));
  for (const child of [...roster.children]) if (!identities.has(child.dataset.identity)) child.remove();
  for (const participant of room.participants) {
    let row = [...roster.children].find((node) => node.dataset.identity === participant.identity);
    if (!row) {
      row = document.createElement("section");
      row.dataset.identity = participant.identity;
      row.append(document.createElement("strong"), document.createElement("small"));
      roster.append(row);
    }
    row.querySelector("strong").textContent = `${participant.identity}${participant.identity === room.identity ? " (you)" : ""}`;
    row.querySelector("small").textContent = participant.role === "listener" ? "Listening" : participant.muted ? "Microphone muted" : "Microphone on";
    const remote = room.remoteAudio.find((r) => r.participant.identity === participant.identity);
    let audio = row.querySelector("audio");
    if (remote) {
      if (!audio) {
        audio = document.createElement("audio");
        audio.autoplay = audio.controls = true;
        audio.setAttribute("aria-label", `Audio from ${participant.identity}`);
        row.append(audio);
      }
      if (audio.srcObject?.getAudioTracks()[0] !== remote.track) {
        audio.srcObject = new MediaStream([remote.track]);
        audio.play().catch(() => { $("status").textContent = "Press play on a participant to allow audio playback."; });
      }
    } else if (audio) audio.remove();
  }
}

room.addEventListener("participants", render);
room.addEventListener("tracks", render);
room.addEventListener("state", ({ detail }) => {
  $("status").textContent = detail.reason || `Media: ${detail.state}`;
  if (detail.state === "disconnected") {
    attempt = null;
    muted = false;
    $("mute").textContent = "Mute microphone";
    controls(false);
  }
});

$("join-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  if (attempt) return;
  const current = attempt = {};
  controls(true);
  $("mute").disabled = true;
  $("status").textContent = "Joining room…";
  try {
    let role = $("role").value;
    let token = $("token").value.trim();
    if (authenticated) {
      const response = await fetch(`/rooms/${encodeURIComponent($("room").value)}/join`, {
        method: "POST", headers: { "x-csrf-token": $("join-form").dataset.csrf, "Accept": "application/json" },
      });
      if (!response.ok || !response.headers.get("content-type")?.includes("application/json")) throw new Error("Please log in again or ask the room owner for access.");
      ({ token, role } = await response.json());
    } else if (!token) {
      const response = await fetch("/dev/token", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ room: $("room").value, identity: $("identity").value, role }),
      });
      if (!response.ok) throw new Error("Provide an access token; local demo access is unavailable.");
      ({ token } = await response.json());
    }
    if (attempt !== current) return;
    await room.join({ room: $("room").value, token, role });
    if (attempt === current) $("mute").disabled = role === "listener";
  } catch (error) {
    if (attempt === current) room.leave(error.message);
  }
});

$("leave").addEventListener("click", () => { attempt = null; room.leave(); });
$("mute").addEventListener("click", async () => {
  const current = attempt;
  $("mute").disabled = true;
  try {
    await room.setMuted(!muted);
    if (attempt !== current) return;
    muted = !muted;
    $("mute").textContent = muted ? "Unmute microphone" : "Mute microphone";
  } catch (error) {
    if (attempt === current) $("status").textContent = error.message;
  } finally {
    if (attempt === current && current) $("mute").disabled = false;
  }
});
window.addEventListener("pagehide", () => room.leave());
$("join").disabled = false;
$("join-form").dataset.ready = "true";
