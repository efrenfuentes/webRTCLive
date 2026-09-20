/*!
 * This bundle includes Phoenix JavaScript, Copyright (c) 2014 Chris McCord.
 * MIT License
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 * of the Software, and to permit persons to whom the Software is furnished to do
 * so, subject to the following conditions:
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
import { Socket, type Channel } from "phoenix";

export type Role = "participant" | "publisher" | "listener";
export interface Participant { identity: string; slot: number; role: Role; muted: boolean }
export interface JoinOptions { url?: string; room: string; token: string; role?: Role }
export interface RemoteAudio { participant: Participant; track: MediaStreamTrack }
export interface RoomEvents {
  participants: Participant[];
  tracks: RemoteAudio[];
  state: { state: RTCPeerConnectionState; reason?: string };
}

interface Session {
  socket?: Socket;
  channel?: Channel;
  pc?: RTCPeerConnection;
  stream?: MediaStream;
  tracks: Map<number, MediaStreamTrack>;
}

/** One local microphone and up to three remote speakers on a single WebRTC connection. */
export class Room extends EventTarget {
  identity: string | null = null;
  participants: Participant[] = [];
  state: RTCPeerConnectionState = "disconnected";
  private current: Session | null = null;

  get remoteAudio(): RemoteAudio[] {
    return this.participants.flatMap((participant) => {
      const track = this.current?.tracks.get(participant.slot);
      return participant.identity !== this.identity && participant.role !== "listener" && track
        ? [{ participant, track }] : [];
    });
  }

  /** Typed event subscription. Returns an unsubscribe function. */
  on<K extends keyof RoomEvents>(name: K, handler: (detail: RoomEvents[K]) => void): () => void {
    const listener = (event: Event) => handler((event as CustomEvent<RoomEvents[K]>).detail);
    this.addEventListener(name, listener);
    return () => this.removeEventListener(name, listener);
  }

  private emit<K extends keyof RoomEvents>(name: K, detail: RoomEvents[K]): void {
    this.dispatchEvent(new CustomEvent(name, { detail }));
  }

  private setState(state: RTCPeerConnectionState, reason?: string): void {
    this.state = state;
    this.emit("state", { state, reason });
  }

  async join({ url = location.origin, room, token, role = "participant" }: JoinOptions): Promise<void> {
    if (this.current) throw new Error("Already joining or joined a room");
    const session: Session = { tracks: new Map() };
    this.current = session;
    const active = () => this.current === session;
    const check = () => { if (!active()) throw new Error("Join cancelled"); };
    const fail = (reason: string) => { if (active()) this.leave(reason); };
    this.setState("connecting");

    try {
      const response = await fetch(new URL("/config", url), { headers: { Authorization: `Bearer ${token}` } });
      if (!response.ok) throw new Error("Access token is invalid or expired");
      const configuration: RTCConfiguration = await response.json();
      check();
      if (role !== "listener") {
        if (!navigator.mediaDevices) throw new Error("Microphone access requires HTTPS or localhost");
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false });
        if (!active()) { stream.getTracks().forEach((t) => t.stop()); check(); }
        session.stream = stream;
      }
      const pc = session.pc = new RTCPeerConnection(configuration);
      const microphone = session.stream?.getAudioTracks()[0];
      pc.addTransceiver(microphone ?? "audio", {
        direction: microphone ? "sendonly" : "inactive",
        ...(session.stream ? { streams: [session.stream] } : {}),
      });
      const receivers = Array.from({ length: 4 }, () => pc.addTransceiver("audio", {
        direction: role === "publisher" ? "inactive" : "recvonly",
      }));
      pc.ontrack = ({ track, transceiver }) => {
        if (!active()) return;
        const slot = receivers.indexOf(transceiver);
        if (slot >= 0) session.tracks.set(slot, track);
        this.emit("tracks", this.remoteAudio);
      };
      pc.onconnectionstatechange = () => {
        if (!active()) return;
        if (["failed", "closed", "disconnected"].includes(pc.connectionState)) return fail("Media connection lost. Join again.");
        this.setState(pc.connectionState);
      };

      const endpoint = new URL("/socket", url);
      endpoint.protocol = endpoint.protocol === "https:" ? "wss:" : "ws:";
      const socket = session.socket = new Socket(endpoint.href, { params: { token } });
      socket.onError(() => fail("Signaling connection lost. Join again."));
      socket.onClose(() => fail("Signaling connection closed. Join again."));
      const channel = session.channel = socket.channel(`room:${room}`, { role });
      channel.onError(() => fail("Room connection lost. Join again."));
      channel.onClose(() => fail("Room closed. Join again."));
      channel.on("ended", ({ reason }: { reason: string }) => fail(reason));
      channel.on("participants", ({ participants }: { participants: Participant[] }) => {
        if (!active()) return;
        this.participants = participants;
        this.emit("participants", participants);
        this.emit("tracks", this.remoteAudio);
      });

      const remoteCandidates: RTCIceCandidateInit[] = [];
      let remoteReady = false;
      channel.on("ice", async (candidate: RTCIceCandidateInit) => {
        try {
          if (!active()) return;
          if (!remoteReady) remoteCandidates.push(candidate);
          else await pc.addIceCandidate(candidate);
        } catch (error) { fail(String(error)); }
      });
      socket.connect();
      const joined = await new Promise<{ identity: string }>((resolve, reject) => {
        channel.join(10000).receive("ok", resolve)
          .receive("error", ({ reason }: { reason: string }) => reject(new Error(reason)))
          .receive("timeout", () => reject(new Error("Room join timed out")));
      });
      check();
      this.identity = joined.identity;
      this.emit("participants", this.participants);

      const localCandidates: RTCIceCandidateInit[] = [];
      let offerAccepted = false;
      pc.onicecandidate = ({ candidate }) => {
        if (!candidate || !active()) return;
        if (offerAccepted) channel.push("ice", candidate.toJSON());
        else localCandidates.push(candidate.toJSON());
      };
      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      const answer = await request<RTCSessionDescriptionInit>(channel, "offer", { type: offer.type, sdp: offer.sdp });
      check();
      offerAccepted = true;
      localCandidates.forEach((candidate) => channel.push("ice", candidate));
      await pc.setRemoteDescription(answer);
      remoteReady = true;
      for (const candidate of remoteCandidates) await pc.addIceCandidate(candidate);
      check();
      this.emit("tracks", this.remoteAudio);
    } catch (error) {
      if (active()) this.leave(error instanceof Error ? error.message : String(error));
      throw error;
    }
  }

  async setMuted(muted: boolean): Promise<void> {
    const session = this.current;
    const track = session?.stream?.getAudioTracks()[0];
    if (!session?.channel || !track) throw new Error("No microphone published");
    // Disable capture transmission immediately; only enable after authorization succeeds.
    if (muted) track.enabled = false;
    await request(session.channel, "mute", { muted });
    if (this.current === session) track.enabled = !muted;
  }

  leave(reason = "Disconnected"): void {
    const session = this.current;
    this.current = null;
    session?.stream?.getTracks().forEach((track) => track.stop());
    session?.pc?.close();
    session?.socket?.disconnect();
    this.identity = null;
    this.participants = [];
    this.emit("participants", []);
    this.emit("tracks", []);
    this.setState("disconnected", reason);
  }
}

function request<T>(channel: Channel, event: string, payload: object): Promise<T> {
  return new Promise((resolve, reject) => {
    channel.push(event, payload, 10000).receive("ok", resolve)
      .receive("error", ({ reason }: { reason: string }) => reject(new Error(reason)))
      .receive("timeout", () => reject(new Error("Signaling timed out")));
  });
}
