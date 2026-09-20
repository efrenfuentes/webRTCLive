defmodule WebRTCLive.Router do
  use Plug.Router
  plug(:match)
  plug(:dispatch)

  get "/" do
    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, Application.app_dir(:webrtc_live, "priv/static/index.html"))
  end

  get "/health" do
    send_resp(conn, 200, "ok")
  end

  get "/config" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      200,
      Jason.encode!(%{iceServers: Application.get_env(:webrtc_live, :ice_servers)})
    )
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
