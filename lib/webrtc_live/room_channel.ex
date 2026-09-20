defmodule WebRTCLive.RoomChannel do
  use Phoenix.Channel
  alias ExWebRTC.{PeerConnection, MediaStreamTrack, SessionDescription, ICECandidate}

  @impl true
  def join("room:" <> name, %{"role" => role}, socket)
      when role in ["publisher", "listener"] do
    with true <- WebRTCLive.Access.valid_name?(name),
         {:ok, claims} <- WebRTCLive.Access.authorize(socket.assigns[:token], name, role),
         :ok <- WebRTCLive.Admission.acquire() do
      case join_authorized(name, role, claims.identity, socket) do
        {:ok, _} = result ->
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

      case WebRTCLive.Room.join(room, role, %{pc: pc, track: track.id, identity: identity}) do
        :ok ->
          Process.monitor(room)

          timer =
            Process.send_after(
              self(),
              :connect_timeout,
              Application.fetch_env!(:webrtc_live, :connect_timeout_ms)
            )

          {:ok,
           assign(socket,
             pc: pc,
             room: room,
             role: role,
             identity: identity,
             destination: nil,
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
    expected = if role == :publisher, do: :sendonly, else: :recvonly

    with {:ok, %{media: [%{type: :audio} = media]}} <- ExSDP.parse(sdp) do
      directions =
        Enum.filter(media.attributes, &(&1 in [:sendonly, :recvonly, :sendrecv, :inactive]))

      directions == [expected] and media.port > 0
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
        %{assigns: %{pc: pc, role: :publisher}} = socket
      ) do
    if destination = socket.assigns.destination do
      PeerConnection.send_rtp(destination.pc, destination.track, packet)
    end

    {:noreply, socket}
  end

  def handle_info({:ex_webrtc, _, {:connection_state_change, state}}, socket)
      when state in [:failed, :closed],
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
    if timer = socket.assigns[:connect_timer], do: Process.cancel_timer(timer)
    if pc = socket.assigns[:pc], do: PeerConnection.stop(pc)
    :ok
  end
end
