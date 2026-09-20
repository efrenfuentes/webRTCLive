defmodule WebRTCLive.RoomChannel do
  use Phoenix.Channel
  alias ExWebRTC.{PeerConnection, MediaStreamTrack, SessionDescription, ICECandidate}

  @impl true
  def join("room:" <> name, %{"role" => role}, socket)
      when role in ["publisher", "listener"] do
    if Regex.match?(~r/\A[a-zA-Z0-9_-]{1,64}\z/, name) do
      role = if role == "publisher", do: :publisher, else: :listener

      servers =
        Enum.map(Application.get_env(:webrtc_live, :ice_servers), fn server ->
          %{urls: server["urls"], username: server["username"], credential: server["credential"]}
        end)

      {:ok, pc} =
        PeerConnection.start_link(
          ice_servers: servers,
          audio_codecs: [
            %ExWebRTC.RTPCodecParameters{
              payload_type: 111,
              mime_type: "audio/opus",
              clock_rate: 48_000,
              channels: 2
            }
          ],
          video_codecs: []
        )

      track = MediaStreamTrack.new(:audio)
      if role == :listener, do: PeerConnection.add_track(pc, track)
      {:ok, room} = WebRTCLive.Room.get_or_start(name)

      case WebRTCLive.Room.join(room, role, %{pc: pc, track: track.id}) do
        :ok ->
          Process.monitor(room)

          {:ok,
           assign(socket, pc: pc, room: room, role: role, destination: nil, negotiated: false)}

        {:error, reason} ->
          PeerConnection.stop(pc)
          {:error, %{reason: reason}}
      end
    else
      {:error, %{reason: "invalid_room"}}
    end
  end

  def join(_, _, _), do: {:error, %{reason: "invalid_role"}}

  @impl true
  def handle_in("offer", %{"type" => "offer", "sdp" => sdp}, socket)
      when is_binary(sdp) and byte_size(sdp) < 65_536 do
    pc = socket.assigns.pc

    with false <- socket.assigns.negotiated,
         :ok <-
           PeerConnection.set_remote_description(pc, %SessionDescription{type: :offer, sdp: sdp}),
         {:ok, answer} <- PeerConnection.create_answer(pc),
         :ok <- PeerConnection.set_local_description(pc, answer) do
      {:reply, {:ok, SessionDescription.to_json(answer)}, assign(socket, :negotiated, true)}
    else
      _ -> {:reply, {:error, %{reason: "invalid_offer"}}, socket}
    end
  end

  def handle_in(
        "ice",
        %{"candidate" => value, "sdpMid" => mid, "sdpMLineIndex" => index} = candidate,
        socket
      )
      when is_binary(value) and byte_size(value) < 4096 and (is_binary(mid) or is_nil(mid)) and
             (is_integer(index) or is_nil(index)) do
    with :ok <-
           PeerConnection.add_ice_candidate(socket.assigns.pc, ICECandidate.from_json(candidate)) do
      {:noreply, socket}
    else
      _ -> {:reply, {:error, %{reason: "invalid_candidate"}}, socket}
    end
  end

  def handle_in(_, _, socket), do: {:reply, {:error, %{reason: "invalid_message"}}, socket}

  @impl true
  def handle_info({:ex_webrtc, pc, {:ice_candidate, candidate}}, %{assigns: %{pc: pc}} = socket) do
    push(socket, "ice", ICECandidate.to_json(candidate))
    {:noreply, socket}
  end

  def handle_info(
        {:ex_webrtc, pc, {:rtp, _, _, packet}},
        %{assigns: %{pc: pc, role: :publisher}} = socket
      ) do
    if destination = socket.assigns.destination do
      PeerConnection.send_rtp(destination.pc, destination.track, packet)
    end

    {:noreply, socket}
  end

  def handle_info({:ex_webrtc, _, {:connection_state_change, :failed}}, socket),
    do: {:stop, :normal, socket}

  def handle_info({:destination, destination}, socket),
    do: {:noreply, assign(socket, :destination, destination)}

  def handle_info({:members, roles}, socket) do
    push(socket, "members", %{roles: roles})
    {:noreply, socket}
  end

  def handle_info(:publisher_left, socket) do
    push(socket, "ended", %{reason: "Publisher left. Join again for a new session."})
    {:stop, :normal, socket}
  end

  def handle_info({:DOWN, _, :process, room, _}, %{assigns: %{room: room}} = socket),
    do: {:stop, :normal, socket}

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def terminate(_, socket) do
    if pc = socket.assigns[:pc], do: PeerConnection.stop(pc)
    :ok
  end
end
