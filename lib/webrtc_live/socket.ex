defmodule WebRTCLive.Socket do
  use Phoenix.Socket
  channel("room:*", WebRTCLive.RoomChannel)

  def connect(%{"token" => token}, socket, _info) do
    case WebRTCLive.Access.verify(token) do
      {:ok, claims} ->
        {:ok, socket |> assign(:token, token) |> assign(:session_id, claims[:session_id])}

      _ ->
        :error
    end
  end

  def connect(_, _, _), do: :error
  def id(%{assigns: %{session_id: id}}) when not is_nil(id), do: "user_session:#{id}"
  def id(_socket), do: nil
end
