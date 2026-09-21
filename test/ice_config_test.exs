defmodule WebRTCLive.IceConfigTest do
  use ExUnit.Case, async: false

  setup do
    old = Application.get_env(:webrtc_live, :turn)

    on_exit(fn ->
      if old,
        do: Application.put_env(:webrtc_live, :turn, old),
        else: Application.delete_env(:webrtc_live, :turn)
    end)

    :ok
  end

  test "TURN is optional" do
    Application.delete_env(:webrtc_live, :turn)

    assert WebRTCLive.IceConfig.for_identity("alice") == %{
             iceServers: Application.get_env(:webrtc_live, :ice_servers)
           }
  end

  test "credentials are expiring identity-bound HMACs, not the shared secret" do
    secret = String.duplicate("test-secret-", 4)
    urls = ["turn:example.test:3478?transport=udp"]
    Application.put_env(:webrtc_live, :turn, %{secret: secret, urls: urls, ttl: 86400})
    %{iceServers: servers} = WebRTCLive.IceConfig.for_identity("alice", 1000)
    grant = List.last(servers)
    assert grant.username == "87400:alice"
    assert grant.urls == urls
    assert grant.credential == Base.encode64(:crypto.mac(:hmac, :sha, secret, "87400:alice"))
    refute Jason.encode!(grant) =~ secret
    refute WebRTCLive.IceConfig.for_identity("bob", 1000) == %{iceServers: servers}
  end
end
