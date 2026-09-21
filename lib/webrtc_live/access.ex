defmodule WebRTCLive.Access do
  @moduledoc "Short-lived, signed admission grants. Tokens are not LiveKit JWTs."
  @salt "room-access-v1"
  @max_age 300

  def issue_for_session(room, role, session_token) do
    with %{id: session_id, user_id: user_id} <-
           WebRTCLive.Repo.get_by(WebRTCLive.Accounts.UserToken,
             token: session_token,
             context: "session"
           ),
         {user, _} <- WebRTCLive.Accounts.get_user_by_session_token(session_token),
         {%{id: room_id}, ^role} <- WebRTCLive.Calls.access(user, room) do
      {:ok,
       Phoenix.Token.sign(WebRTCLive.Endpoint, @salt, %{
         room: room,
         room_id: room_id,
         identity: "u#{user_id}",
         role: role,
         session_id: session_id
       })}
    else
      _ -> {:error, :unauthorized}
    end
  end

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
             role in ["publisher", "listener", "participant"],
         true <- session_valid?(claims) do
      {:ok, claims}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def verify(_), do: {:error, :unauthorized}

  defp session_valid?(%{session_id: id, room: room, role: role, identity: identity} = claims) do
    with %{token: token, context: "session"} <-
           WebRTCLive.Repo.get(WebRTCLive.Accounts.UserToken, id),
         {user, _} <- WebRTCLive.Accounts.get_user_by_session_token(token),
         {%{id: room_id}, ^role} <- WebRTCLive.Calls.access(user, room) do
      identity == "u#{user.id}" and claims[:room_id] == room_id
    else
      _ -> false
    end
  end

  # Trusted server-side issuers retain the explicit service/SDK token API.
  defp session_valid?(_), do: true

  def authorize(token, room, role) do
    case verify(token) do
      {:ok, %{room: ^room, role: ^role} = claims} -> {:ok, claims}
      _ -> {:error, :unauthorized}
    end
  end

  def valid_name?(name) when is_binary(name), do: Regex.match?(~r/\A[a-zA-Z0-9_-]{1,64}\z/, name)
  def valid_name?(_), do: false
end
