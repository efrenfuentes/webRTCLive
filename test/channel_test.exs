defmodule WebRTCLive.RoomChannelTest do
  use ExUnit.Case, async: false
  import Phoenix.ChannelTest
  @endpoint WebRTCLive.Endpoint

  setup do
    {:ok, socket} = connect(WebRTCLive.Socket, %{})
    %{socket: socket, topic: "room:test-#{System.unique_integer([:positive])}"}
  end

  test "validates room names and roles", %{socket: socket} do
    assert {:error, %{reason: "invalid_room"}} =
             subscribe_and_join(socket, "room:bad room", %{role: "publisher"})

    assert {:error, %{reason: "invalid_role"}} =
             subscribe_and_join(socket, "room:valid", %{role: "other"})
  end

  test "rejects a second publisher and malformed signaling", %{socket: socket, topic: topic} do
    {:ok, _, joined} = subscribe_and_join(socket, topic, %{role: "publisher"})

    assert {:error, %{reason: :role_taken}} =
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

    {:ok, offer} = PeerConnection.create_offer(client)
    :ok = PeerConnection.set_local_description(client, offer)
    {:ok, _, joined} = subscribe_and_join(socket, topic, %{role: "publisher"})
    server = joined.assigns.pc
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
