defmodule WebRTCLive.Access do
  @moduledoc "Short-lived, signed admission grants. Tokens are not LiveKit JWTs."
  @salt "room-access-v1"
  @max_age 300

  def issue(room, identity, role) do
    if valid_name?(room) and valid_name?(identity) and
         role in ["publisher", "listener", "participant"] do
      {:ok,
       Phoenix.Token.sign(WebRTCLive.Endpoint, @salt, %{
         room: room,
         identity: identity,
         role: role
       })}
    else
      {:error, :invalid_grant}
    end
  end

  def verify(token) when is_binary(token) and byte_size(token) <= 4096 do
    with {:ok, %{room: room, identity: identity, role: role} = claims} <-
           Phoenix.Token.verify(WebRTCLive.Endpoint, @salt, token, max_age: @max_age),
         true <-
           valid_name?(room) and valid_name?(identity) and
             role in ["publisher", "listener", "participant"] do
      {:ok, claims}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def verify(_), do: {:error, :unauthorized}

  def authorize(token, room, role) do
    case verify(token) do
      {:ok, %{room: ^room, role: ^role} = claims} -> {:ok, claims}
      _ -> {:error, :unauthorized}
    end
  end

  def valid_name?(name) when is_binary(name), do: Regex.match?(~r/\A[a-zA-Z0-9_-]{1,64}\z/, name)
  def valid_name?(_), do: false
end
