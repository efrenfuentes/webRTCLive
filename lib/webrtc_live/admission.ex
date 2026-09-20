defmodule WebRTCLive.Admission do
  @moduledoc "Atomic session capacity reservations, released when their owner exits."
  use GenServer

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def acquire(server \\ __MODULE__), do: GenServer.call(server, :acquire)
  def release(server \\ __MODULE__), do: GenServer.call(server, :release)

  @impl true
  def init(opts), do: {:ok, %{limit: Keyword.fetch!(opts, :limit), owners: %{}}}

  @impl true
  def handle_call(:acquire, {pid, _}, state) do
    cond do
      Map.has_key?(state.owners, pid) -> {:reply, :ok, state}
      map_size(state.owners) >= state.limit -> {:reply, {:error, :capacity_reached}, state}
      true -> {:reply, :ok, put_in(state.owners[pid], Process.monitor(pid))}
    end
  end

  def handle_call(:release, {pid, _}, state) do
    if ref = state.owners[pid], do: Process.demonitor(ref, [:flush])
    {:reply, :ok, %{state | owners: Map.delete(state.owners, pid)}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _}, state) do
    if state.owners[pid] == ref do
      {:noreply, %{state | owners: Map.delete(state.owners, pid)}}
    else
      {:noreply, state}
    end
  end
end
