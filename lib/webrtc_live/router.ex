defmodule WebRTCLive.Router do
  use Plug.Router
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason, length: 8192)
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
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, _} <- WebRTCLive.Access.verify(token) do
      json(conn, 200, %{iceServers: Application.get_env(:webrtc_live, :ice_servers)})
    else
      _ -> json(conn, 401, %{error: "unauthorized"})
    end
  end

  post "/dev/token" do
    # No public token issuer is enabled outside local development.
    if Application.get_env(:webrtc_live, :demo_tokens, false) do
      with %{"room" => room, "identity" => identity, "role" => role} <- conn.body_params,
           {:ok, token} <- WebRTCLive.Access.issue(room, identity, role) do
        json(conn, 200, %{token: token})
      else
        _ -> json(conn, 400, %{error: "invalid_grant"})
      end
    else
      send_resp(conn, 404, "Not found")
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
