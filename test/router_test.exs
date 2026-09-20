defmodule WebRTCLive.RouterTest do
  use ExUnit.Case, async: true
  import Plug.Test

  test "serves demo, browser module, bundled Phoenix client, config and health" do
    for path <- ["/", "/client.js", "/vendor/phoenix.mjs", "/config", "/health"] do
      conn = WebRTCLive.Endpoint.call(conn(:get, path), WebRTCLive.Endpoint.init([]))
      assert conn.status == 200, "#{path} returned #{conn.status}"
    end
  end
end
