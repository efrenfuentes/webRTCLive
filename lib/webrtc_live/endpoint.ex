defmodule WebRTCLive.Endpoint do
  use Phoenix.Endpoint, otp_app: :webrtc_live
  socket("/socket", WebRTCLive.Socket, websocket: true, longpoll: false)
  plug(Plug.Static, at: "/vendor", from: {:phoenix, "priv/static"}, only: ~w(phoenix.mjs))
  plug(Plug.Static, at: "/", from: :webrtc_live, only: ~w(index.html client.js))
  plug(WebRTCLive.Router)
end
