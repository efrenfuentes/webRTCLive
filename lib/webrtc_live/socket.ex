defmodule WebRTCLive.Socket do
  use Phoenix.Socket
  channel("room:*", WebRTCLive.RoomChannel)

  def connect(%{"token" => token}, socket, _info) do
    case WebRTCLive.Access.verify(token) do
      {:ok, _} -> {:ok, assign(socket, :token, token)}
      _ -> :error
    end
  end

  def connect(_, _, _), do: :error
  def id(_socket), do: nil
end
