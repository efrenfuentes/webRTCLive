defmodule WebRTCLive.RoomChannelTest do
  use ExUnit.Case, async: false
  import Phoenix.ChannelTest
  @endpoint WebRTCLive.Endpoint

  setup do
    room = "test-#{System.unique_integer([:positive])}"
    {:ok, token} = WebRTCLive.Access.issue(room, "alice", "publisher")
    {:ok, socket} = connect(WebRTCLive.Socket, %{"token" => token})
    %{socket: socket, topic: "room:#{room}", room: room}
  end

  test "socket requires a signed token" do
    assert :error = connect(WebRTCLive.Socket, %{})
    assert :error = connect(WebRTCLive.Socket, %{"token" => "forged"})
  end

  test "participant negotiates one upload and four receive slots", %{room: room, topic: topic} do
    alias ExWebRTC.{PeerConnection, MediaStreamTrack, SessionDescription}
    {:ok, token} = WebRTCLive.Access.issue(room, "alice", "participant")
    {:ok, socket} = connect(WebRTCLive.Socket, %{"token" => token})
    {:ok, client} = PeerConnection.start_link()

    {:ok, _} =
      PeerConnection.add_transceiver(client, MediaStreamTrack.new(:audio), direction: :sendonly)

    for _ <- 1..4, do: PeerConnection.add_transceiver(client, :audio, direction: :recvonly)
    {:ok, offer} = PeerConnection.create_offer(client)
    :ok = PeerConnection.set_local_description(client, offer)

    {:ok, %{identity: "alice", capacity: 4}, joined} =
      subscribe_and_join(socket, topic, %{role: "participant"})

    ref = push(joined, "offer", SessionDescription.to_json(offer))
    assert_reply(ref, :ok, %{"sdp" => answer}, 2000)
    assert length(Regex.scan(~r/a=sendonly/, answer)) == 4
    assert length(Regex.scan(~r/a=recvonly/, answer)) == 1

    assert :ok =
             PeerConnection.set_remote_description(client, %SessionDescription{
               type: :answer,
               sdp: answer
             })

    PeerConnection.stop(client)
  end

  test "tokens cannot change room or permission", %{socket: socket, topic: topic} do
    assert {:error, %{reason: :unauthorized}} =
             subscribe_and_join(socket, topic, %{role: "listener"})

    assert {:error, %{reason: :unauthorized}} =
             subscribe_and_join(socket, "room:other", %{role: "publisher"})
  end

  test "participant identities must be unique in a room", %{
    socket: socket,
    topic: topic,
    room: room
  } do
    {:ok, _, _} = subscribe_and_join(socket, topic, %{role: "publisher"})
    {:ok, token} = WebRTCLive.Access.issue(room, "alice", "listener")
    {:ok, listener} = connect(WebRTCLive.Socket, %{"token" => token})

    assert {:error, %{reason: :identity_taken}} =
             subscribe_and_join(listener, topic, %{role: "listener"})
  end

  test "signaling flood closes the session", %{socket: socket, topic: topic} do
    {:ok, _, joined} = subscribe_and_join(socket, topic, %{role: "publisher"})
    Process.unlink(joined.channel_pid)
    monitor = Process.monitor(joined.channel_pid)
    for _ <- 1..101, do: push(joined, "unknown", %{})
    assert_push("ended", %{reason: "Signaling rate limit exceeded."})
    assert_receive {:DOWN, ^monitor, :process, _, _}, 2000
  end

  test "unconnected sessions expire", %{socket: socket, topic: topic} do
    {:ok, _, joined} = subscribe_and_join(socket, topic, %{role: "publisher"})
    Process.unlink(joined.channel_pid)
    monitor = Process.monitor(joined.assigns.pc)
    send(joined.channel_pid, :connect_timeout)
    assert_push("ended", %{reason: "Media connection timed out."})
    assert_receive {:DOWN, ^monitor, :process, _, _}, 2000
  end

  test "validates room names and roles", %{socket: socket} do
    assert {:error, %{reason: "invalid_room"}} =
             subscribe_and_join(socket, "room:bad room", %{role: "publisher"})

    assert {:error, %{reason: "invalid_role"}} =
             subscribe_and_join(socket, "room:valid", %{role: "other"})
  end

  test "rejects a duplicate identity and malformed signaling", %{socket: socket, topic: topic} do
    {:ok, _, joined} = subscribe_and_join(socket, topic, %{role: "publisher"})

    assert {:error, %{reason: :identity_taken}} =
             subscribe_and_join(socket, topic, %{role: "publisher"})

    ref = push(joined, "ice", %{})
    assert_reply(ref, :error, %{reason: "invalid_message"})
    ref = push(joined, "offer", %{type: "offer", sdp: "invalid"})
    assert_reply(ref, :error, %{reason: "invalid_offer"})
    ref = push(joined, "unknown", %{})
    assert_reply(ref, :error, %{reason: "invalid_message"})
  end

  test "negotiates an Opus publisher and stops its peer on leave", %{socket: socket, topic: topic} do
    alias ExWebRTC.{PeerConnection, MediaStreamTrack, SessionDescription}
    {:ok, client} = PeerConnection.start_link()

    {:ok, _} =
      PeerConnection.add_transceiver(client, MediaStreamTrack.new(:audio), direction: :sendonly)

    for _ <- 1..4, do: PeerConnection.add_transceiver(client, :audio, direction: :inactive)

    {:ok, offer} = PeerConnection.create_offer(client)
    :ok = PeerConnection.set_local_description(client, offer)
    {:ok, _, joined} = subscribe_and_join(socket, topic, %{role: "publisher"})
    server = joined.assigns.pc
    # A publish grant must not negotiate receive or bidirectional media.
    invalid = %{offer | sdp: String.replace(offer.sdp, "a=sendonly", "a=sendrecv")}
    ref = push(joined, "offer", SessionDescription.to_json(invalid))
    assert_reply(ref, :error, %{reason: "invalid_offer"})
    ref = push(joined, "offer", SessionDescription.to_json(offer))
    assert_reply(ref, :ok, %{"type" => "answer", "sdp" => sdp}, 2000)
    assert sdp =~ "opus/48000/2"
    assert sdp =~ "a=recvonly"

    assert :ok =
             PeerConnection.set_remote_description(client, %SessionDescription{
               type: :answer,
               sdp: sdp
             })

    monitor = Process.monitor(server)
    Process.unlink(joined.channel_pid)
    leave(joined)
    assert_receive {:DOWN, ^monitor, :process, ^server, _}, 2000
    PeerConnection.stop(client)
  end
end
