defmodule WebRTCLive.RateLimit do
  @moduledoc "Single-node, bounded fixed-window limits for authentication and invitations."
  use GenServer
  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def init(state), do: {:ok, state}

  def allow?(key, limit, seconds \\ 60),
    do: GenServer.call(__MODULE__, {:allow, key, limit, seconds})

  def handle_call({:allow, key, limit, seconds}, _, state) do
    now = System.monotonic_time(:second)
    state = Map.reject(state, fn {_, {_, expires}} -> expires <= now end)
    {count, expires} = Map.get(state, key, {0, now + seconds})
    allowed = count < limit and (map_size(state) < 10_000 or Map.has_key?(state, key))
    {:reply, allowed, if(allowed, do: Map.put(state, key, {count + 1, expires}), else: state)}
  end
end
