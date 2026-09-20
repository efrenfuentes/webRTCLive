defmodule WebRTCLive.RoomChannel do
  use Phoenix.Channel
  alias ExWebRTC.{PeerConnection, MediaStreamTrack, SessionDescription, ICECandidate}

  @impl true
  def join("room:" <> name, %{"role" => role}, socket)
      when role in ["publisher", "listener", "participant"] do
    with true <- WebRTCLive.Access.valid_name?(name),
         {:ok, claims} <- WebRTCLive.Access.authorize(socket.assigns[:token], name, role),
         :ok <- WebRTCLive.Admission.acquire() do
      case join_authorized(name, role, claims.identity, socket) do
        {:ok, _, _} = result ->
          result

        error ->
          WebRTCLive.Admission.release()
          error
      end
    else
      false -> {:error, %{reason: "invalid_room"}}
      {:error, reason} -> {:error, %{reason: reason}}
    end
  end

  def join(_, _, _), do: {:error, %{reason: "invalid_role"}}

  defp join_authorized(name, role, identity, socket) do
    with {:ok, room} <- WebRTCLive.Room.get_or_start(name) do
      role =
        case role do
          "publisher" -> :publisher
          "listener" -> :listener
          "participant" -> :participant
        end

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

      tracks =
        for slot <- 0..(WebRTCLive.Room.capacity() - 1), into: %{} do
          track = MediaStreamTrack.new(:audio)
          # Only add_track-created senders can be associated with a remote offer.
          # The inbound microphone transceiver is created from that offer itself.
          if role != :publisher, do: PeerConnection.add_track(pc, track)
          {slot, track.id}
        end

      case WebRTCLive.Room.join(room, role, %{identity: identity}) do
        {:ok, slot} ->
          Process.monitor(room)

          timer =
            Process.send_after(
              self(),
              :connect_timeout,
              Application.fetch_env!(:webrtc_live, :connect_timeout_ms)
            )

          {:ok, %{identity: identity, slot: slot, capacity: WebRTCLive.Room.capacity()},
           assign(socket,
             pc: pc,
             room: room,
             role: role,
             identity: identity,
             slot: slot,
             destinations: [],
             sources: %{},
             tracks: tracks,
             continuity: %{},
             muted: role == :listener,
             negotiated: false,
             connect_timer: timer,
             connected: false,
             signal_window: System.monotonic_time(:millisecond),
             signal_count: 0
           )}

        {:error, reason} ->
          PeerConnection.stop(pc)
          {:error, %{reason: reason}}
      end
    else
      {:error, :max_children} -> {:error, %{reason: :capacity_reached}}
      {:error, _} -> {:error, %{reason: :room_unavailable}}
    end
  end

  @impl true
  def handle_in(event, payload, socket) do
    now = System.monotonic_time(:millisecond)

    socket =
      if now - socket.assigns.signal_window >= 10_000,
        do: assign(socket, signal_window: now, signal_count: 0),
        else: socket

    if socket.assigns.signal_count >= 100 do
      push(socket, "ended", %{reason: "Signaling rate limit exceeded."})
      {:stop, :normal, socket}
    else
      handle_signal(
        event,
        payload,
        assign(socket, :signal_count, socket.assigns.signal_count + 1)
      )
    end
  end

  defp handle_signal("offer", %{"type" => "offer", "sdp" => sdp}, socket)
       when is_binary(sdp) and byte_size(sdp) < 65_536 do
    pc = socket.assigns.pc

    with false <- socket.assigns.negotiated,
         true <- valid_offer?(sdp, socket.assigns.role),
         :ok <-
           PeerConnection.set_remote_description(pc, %SessionDescription{type: :offer, sdp: sdp}),
         {:ok, answer} <- PeerConnection.create_answer(pc),
         :ok <- PeerConnection.set_local_description(pc, answer) do
      {:reply, {:ok, SessionDescription.to_json(answer)}, assign(socket, :negotiated, true)}
    else
      _ -> {:reply, {:error, %{reason: "invalid_offer"}}, socket}
    end
  end

  defp handle_signal("mute", %{"muted" => muted}, socket) when is_boolean(muted) do
    case WebRTCLive.Room.mute(socket.assigns.room, muted) do
      :ok -> {:reply, {:ok, %{}}, assign(socket, :muted, muted)}
      {:error, reason} -> {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  defp handle_signal(
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

  defp handle_signal(_, _, socket), do: {:reply, {:error, %{reason: "invalid_message"}}, socket}

  defp valid_offer?(sdp, role) do
    expected = [
      if(role == :listener, do: :inactive, else: :sendonly)
      | List.duplicate(
          if(role == :publisher, do: :inactive, else: :recvonly),
          WebRTCLive.Room.capacity()
        )
    ]

    with {:ok, %{media: media}} <- ExSDP.parse(sdp),
         true <- length(media) == length(expected) do
      Enum.zip(media, expected)
      |> Enum.all?(fn {media, direction} ->
        media.type == :audio and media.port > 0 and
          Enum.filter(media.attributes, &(&1 in [:sendonly, :recvonly, :sendrecv, :inactive])) ==
            [direction]
      end)
    else
      _ -> false
    end
  end

  @impl true
  def handle_info(:connect_timeout, %{assigns: %{connected: false}} = socket) do
    push(socket, "ended", %{reason: "Media connection timed out."})
    {:stop, :normal, socket}
  end

  def handle_info(
        {:ex_webrtc, pc, {:connection_state_change, :connected}},
        %{assigns: %{pc: pc}} = socket
      ) do
    Process.cancel_timer(socket.assigns.connect_timer)
    {:noreply, assign(socket, :connected, true)}
  end

  def handle_info({:ex_webrtc, pc, {:ice_candidate, candidate}}, %{assigns: %{pc: pc}} = socket) do
    push(socket, "ice", ICECandidate.to_json(candidate))
    {:noreply, socket}
  end

  def handle_info(
        {:ex_webrtc, pc, {:rtp, _, _, packet}},
        %{assigns: %{pc: pc, role: role, muted: false}} = socket
      )
      when role != :listener do
    Enum.each(socket.assigns.destinations, fn pid ->
      send(pid, {:forward_audio, self(), socket.assigns.slot, packet})
    end)

    {:noreply, socket}
  end

  def handle_info({:ex_webrtc, _, {:connection_state_change, state}}, socket)
      when state in [:failed, :closed],
      do: {:stop, :normal, socket}

  def handle_info({:forward_audio, source, slot, packet}, socket) do
    if socket.assigns.connected and Map.get(socket.assigns.sources, source) == slot do
      {packet, state} =
        WebRTCLive.AudioContinuity.rewrite(packet, source, socket.assigns.continuity[slot])

      PeerConnection.send_rtp(socket.assigns.pc, socket.assigns.tracks[slot], packet)
      {:noreply, assign(socket, :continuity, Map.put(socket.assigns.continuity, slot, state))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:routing, peers}, socket) do
    others = Enum.reject(peers, &(&1.pid == self()))
    destinations = others |> Enum.reject(&(&1.role == :publisher)) |> Enum.map(& &1.pid)

    sources =
      if socket.assigns.role == :publisher,
        do: %{},
        else:
          others
          |> Enum.reject(&(&1.role == :listener or &1.muted))
          |> Map.new(&{&1.pid, &1.slot})

    push(socket, "participants", %{
      participants: Enum.map(peers, &Map.take(&1, [:identity, :slot, :role, :muted]))
    })

    socket = assign(socket, destinations: destinations, sources: sources)
    {:noreply, socket}
  end

  def handle_info({:DOWN, _, :process, room, _}, %{assigns: %{room: room}} = socket),
    do: {:stop, :normal, socket}

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def terminate(_, socket) do
    if timer = socket.assigns[:connect_timer], do: Process.cancel_timer(timer)
    if pc = socket.assigns[:pc], do: PeerConnection.stop(pc)
    :ok
  end
end
