import { Socket } from "/vendor/phoenix.mjs";

const $ = (id) => document.getElementById(id);
let session = null;

function status(text) { $("status").textContent = text; }
function push(channel, event, payload) {
  return new Promise((resolve, reject) => {
    channel.push(event, payload, 10000)
      .receive("ok", resolve)
      .receive("error", (error) => reject(new Error(error.reason || "Signaling failed")))
      .receive("timeout", () => reject(new Error("Signaling timed out")));
  });
}

function leave(message = "Disconnected.") {
  const old = session;
  session = null;
  if (old) {
    old.stream?.getTracks().forEach((track) => track.stop());
    old.pc?.close();
    old.socket?.disconnect();
  }
  $("remote").srcObject = null;
  $("join").disabled = false;
  $("room").disabled = false;
  $("role").disabled = false;
  $("leave").disabled = true;
  $("mute").disabled = true;
  $("mute").textContent = "Mute microphone";
  $("members").textContent = "Room is not connected.";
  status(message);
}

$("join-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  if (session) return;
  const current = {};
  session = current;
  const active = () => session === current;
  const role = $("role").value;
  const room = $("room").value;
  $("join").disabled = $("room").disabled = $("role").disabled = true;
  $("leave").disabled = false;
  status("Connecting…");
  try {
    if (role === "publisher") {
      if (!navigator.mediaDevices) throw new Error("Microphone access requires HTTPS or localhost.");
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false });
      if (!active()) { stream.getTracks().forEach((track) => track.stop()); return; }
      current.stream = stream;
    }
    const response = await fetch("/config");
    if (!response.ok) throw new Error("Could not load connection settings");
    const config = await response.json();
    if (!active()) return;
    const pc = current.pc = new RTCPeerConnection(config);
    if (current.stream) {
      pc.addTransceiver(current.stream.getAudioTracks()[0], { direction: "sendonly", streams: [current.stream] });
    } else {
      pc.addTransceiver("audio", { direction: "recvonly" });
    }
    pc.ontrack = ({ track }) => {
      if (!active()) return;
      $("remote").srcObject = new MediaStream([track]);
      $("remote").play().catch(() => {
        if (active()) status("Audio ready. Press play below to allow playback.");
      });
    };
    pc.onconnectionstatechange = () => {
      if (!active()) return;
      if (pc.connectionState === "failed") return leave("Media connection failed. Check network/TURN settings, then join again.");
      status(`Media: ${pc.connectionState}. ${role === "publisher" ? "Publishing microphone." : "Waiting for publisher audio."}`);
    };
    const socket = current.socket = new Socket("/socket");
    socket.onError(() => { if (active()) leave("Signaling connection lost. Join again."); });
    socket.onClose(() => { if (active()) leave("Signaling connection closed. Join again."); });
    socket.connect();
    const channel = current.channel = socket.channel(`room:${room}`, { role });
    const remoteCandidates = [];
    let remoteReady = false;
    channel.on("ice", async (candidate) => {
      try {
        if (!remoteReady) remoteCandidates.push(candidate);
        else if (active()) await pc.addIceCandidate(candidate);
      } catch (error) { if (active()) leave(error.message); }
    });
    channel.on("members", ({ roles }) => {
      if (active()) $("members").textContent = `In room: ${roles.join(" + ")}`;
    });
    channel.on("ended", ({ reason }) => { if (active()) leave(reason); });
    channel.onError(() => { if (active()) leave("Room connection lost. Join again."); });
    channel.onClose(() => { if (active()) leave("Room closed. Join again."); });
    await new Promise((resolve, reject) => {
      channel.join().receive("ok", resolve)
        .receive("error", ({ reason }) => reject(new Error(reason)))
        .receive("timeout", () => reject(new Error("Room join timed out")));
    });
    if (!active()) return;
    const localCandidates = [];
    let offerAccepted = false;
    pc.onicecandidate = ({ candidate }) => {
      if (!candidate || !active()) return;
      if (offerAccepted) channel.push("ice", candidate.toJSON());
      else localCandidates.push(candidate.toJSON());
    };
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    const answer = await push(channel, "offer", { type: offer.type, sdp: offer.sdp });
    if (!active()) return;
    offerAccepted = true;
    for (const candidate of localCandidates) channel.push("ice", candidate);
    await pc.setRemoteDescription(answer);
    remoteReady = true;
    for (const candidate of remoteCandidates) await pc.addIceCandidate(candidate);
    if (active()) $("mute").disabled = role !== "publisher";
  } catch (error) {
    if (active()) leave(`Could not connect: ${error.message}`);
  }
});

$("leave").addEventListener("click", () => leave());
$("mute").addEventListener("click", () => {
  const track = session?.stream?.getAudioTracks()[0];
  if (!track) return;
  track.enabled = !track.enabled;
  $("mute").textContent = track.enabled ? "Mute microphone" : "Unmute microphone";
});
window.addEventListener("pagehide", () => leave());
