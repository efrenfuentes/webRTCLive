defmodule WebRTCLive.AccessTest do
  use ExUnit.Case, async: true
  alias WebRTCLive.Access

  test "signed grants bind room, identity, and role" do
    {:ok, token} = Access.issue("demo", "alice", "publisher")
    assert {:ok, %{identity: "alice"}} = Access.authorize(token, "demo", "publisher")
    assert {:error, :unauthorized} = Access.authorize(token, "elsewhere", "publisher")
    assert {:error, :unauthorized} = Access.authorize(token, "demo", "listener")
    assert {:error, :unauthorized} = Access.verify(token <> "tampered")
    assert {:error, :unauthorized} = Access.verify(nil)
    assert {:error, :unauthorized} = Access.verify(String.duplicate("x", 4097))
  end

  test "expired and malformed signed grants fail closed" do
    token =
      Phoenix.Token.sign(
        WebRTCLive.Endpoint,
        "room-access-v1",
        %{room: "demo", identity: "alice", role: "publisher"},
        signed_at: System.system_time(:second) - 301
      )

    assert {:error, :unauthorized} = Access.verify(token)
    malformed = Phoenix.Token.sign(WebRTCLive.Endpoint, "room-access-v1", %{room: "demo"})
    assert {:error, :unauthorized} = Access.verify(malformed)
    assert {:error, :invalid_grant} = Access.issue("", "alice", "publisher")
    assert {:error, :invalid_grant} = Access.issue("demo", "alice", "admin")
  end
end
