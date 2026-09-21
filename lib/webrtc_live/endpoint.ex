defmodule WebRTCLive.Endpoint do
  use Phoenix.Endpoint, otp_app: :webrtc_live
  socket("/socket", WebRTCLive.Socket, websocket: [max_frame_size: 131_072], longpoll: false)
  plug(Plug.Static, at: "/vendor", from: {:phoenix, "priv/static"}, only: ~w(phoenix.mjs))
  plug(Plug.Static, at: "/", from: :webrtc_live, only: ~w(index.html client.js sdk.js))
  plug(Plug.RequestId)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Jason,
    length: 8192
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)

  plug(Plug.Session,
    store: :cookie,
    key: "_webrtc_live_session",
    signing_salt: "browser-session-v1",
    same_site: "Lax",
    http_only: true
  )

  plug(WebRTCLiveWeb.Router)
end
