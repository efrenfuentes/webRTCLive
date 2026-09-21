defmodule WebRTCLive.IceConfig do
  @moduledoc "Browser ICE configuration with time-limited TURN credentials."

  def for_identity(identity, now \\ System.system_time(:second)) do
    servers = Application.get_env(:webrtc_live, :ice_servers, [])

    case Application.get_env(:webrtc_live, :turn) do
      nil ->
        %{iceServers: servers}

      %{secret: secret, urls: urls, ttl: ttl} ->
        username = "#{now + ttl}:#{identity}"
        credential = :crypto.mac(:hmac, :sha, secret, username) |> Base.encode64()

        %{iceServers: servers ++ [%{urls: urls, username: username, credential: credential}]}
    end
  end
end
