defmodule WebRTCLive.Socket do
  use Phoenix.Socket
  channel("room:*", WebRTCLive.RoomChannel)
  def connect(_params, socket, _info), do: {:ok, socket}
  def id(_socket), do: nil
end
