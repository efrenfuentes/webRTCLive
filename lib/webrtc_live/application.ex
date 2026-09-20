defmodule WebRTCLive.Application do
  use Application

  def start(_type, _args) do
    Supervisor.start_link(
      [
        {Phoenix.PubSub, name: WebRTCLive.PubSub},
        {Registry, keys: :unique, name: WebRTCLive.Registry},
        {DynamicSupervisor, strategy: :one_for_one, name: WebRTCLive.RoomSupervisor},
        WebRTCLive.Endpoint
      ],
      strategy: :one_for_one,
      name: WebRTCLive.Supervisor
    )
  end
end
