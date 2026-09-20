defmodule WebRTCLive.RouterTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  test "serves demo, browser module, bundled Phoenix client, config and health" do
    for path <- ["/", "/client.js", "/vendor/phoenix.mjs", "/health"] do
      conn = WebRTCLive.Endpoint.call(conn(:get, path), WebRTCLive.Endpoint.init([]))
      assert conn.status == 200, "#{path} returned #{conn.status}"
    end
  end

  test "ICE configuration requires authentication and cannot be cached" do
    assert call(conn(:get, "/config")).status == 401
    {:ok, token} = WebRTCLive.Access.issue("demo", "alice", "listener")

    response =
      conn(:get, "/config") |> put_req_header("authorization", "Bearer #{token}") |> call()

    assert response.status == 200
    assert get_resp_header(response, "cache-control") == ["no-store"]
  end

  test "demo issuer is disabled by default outside dev" do
    assert call(conn(:post, "/dev/token")).status == 404
  end

  test "demo issuer validates grants when explicitly enabled" do
    Application.put_env(:webrtc_live, :demo_tokens, true)
    on_exit(fn -> Application.put_env(:webrtc_live, :demo_tokens, false) end)

    response =
      conn(
        :post,
        "/dev/token",
        Jason.encode!(%{room: "demo", identity: "alice", role: "listener"})
      )
      |> put_req_header("content-type", "application/json")
      |> call()

    assert response.status == 200

    assert {:ok, %{identity: "alice"}} =
             response.resp_body
             |> Jason.decode!()
             |> Map.fetch!("token")
             |> WebRTCLive.Access.verify()

    assert call(conn(:post, "/dev/token")).status == 400
  end

  defp call(conn), do: WebRTCLive.Endpoint.call(conn, WebRTCLive.Endpoint.init([]))
end
