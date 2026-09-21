defmodule WebRTCLiveWeb.RequestLimits do
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _) do
    if conn.method in ["POST", "PUT", "DELETE"] and
         Application.get_env(:webrtc_live, :rate_limits, true) do
      actor =
        case conn.assigns[:current_scope] do
          %{user: user} -> {:user, user.id}
          _ -> {:ip, client_ip(conn)}
        end

      email = get_in(conn.body_params, ["user", "email"])

      permitted =
        WebRTCLive.RateLimit.allow?(actor, 30) and
          (not is_binary(email) or
             WebRTCLive.RateLimit.allow?({:email, String.downcase(String.trim(email))}, 3))

      if permitted,
        do: conn,
        else:
          conn
          |> put_resp_header("retry-after", "60")
          |> send_resp(429, "Too many requests. Try again in a minute.")
          |> halt()
    else
      conn
    end
  end

  # Only Caddy on loopback is trusted to supply the client address.
  defp client_ip(%{remote_ip: {127, 0, 0, 1}} = conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [value] -> value |> String.split(",") |> List.last() |> String.trim()
      _ -> "127.0.0.1"
    end
  end

  defp client_ip(conn), do: conn.remote_ip
end
