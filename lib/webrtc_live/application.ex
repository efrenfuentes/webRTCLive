defmodule WebRTCLive.Application do
  use Application

  def start(_type, _args) do
    Supervisor.start_link(
      [
        {Phoenix.PubSub, name: WebRTCLive.PubSub},
        {Registry, keys: :unique, name: WebRTCLive.Registry},
        {WebRTCLive.Admission, limit: Application.fetch_env!(:webrtc_live, :max_sessions)},
        {DynamicSupervisor,
         strategy: :one_for_one,
         name: WebRTCLive.RoomSupervisor,
         max_children: Application.fetch_env!(:webrtc_live, :max_rooms)},
        WebRTCLive.Endpoint
      ],
      strategy: :rest_for_one,
      name: WebRTCLive.Supervisor
    )
  end
end
