defmodule WebRTCLive.Room do
  @moduledoc "Ephemeral four-person audio room with stable receive slots."
  use GenServer, restart: :temporary

  def start_link(name), do: GenServer.start_link(__MODULE__, name, name: via(name))
  defp via(name), do: {:via, Registry, {WebRTCLive.Registry, name}}

  def get_or_start(name, supervisor \\ WebRTCLive.RoomSupervisor) do
    case Registry.lookup(WebRTCLive.Registry, name) do
      [{pid, _}] -> {:ok, pid}
      [] -> start_room(name, supervisor)
    end
  end

  defp start_room(name, supervisor) do
    case DynamicSupervisor.start_child(supervisor, {__MODULE__, name}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  def join(room, role, peer), do: GenServer.call(room, {:join, role, peer})
  def mute(room, muted), do: GenServer.call(room, {:mute, muted})
  def capacity, do: 4

  @impl true
  def init(_name), do: {:ok, %{}, 30_000}

  @impl true
  def handle_call({:join, role, peer}, {pid, _}, members) do
    cond do
      Enum.any?(members, fn {_, member} -> member.identity == peer.identity end) ->
        {:reply, {:error, :identity_taken}, members}

      map_size(members) >= capacity() ->
        {:reply, {:error, :room_full}, members}

      true ->
        used = Enum.map(members, fn {_, member} -> member.slot end)
        slot = Enum.find(0..(capacity() - 1), &(&1 not in used))

        member =
          Map.merge(peer, %{
            pid: pid,
            monitor: Process.monitor(pid),
            role: role,
            slot: slot,
            muted: role == :listener
          })

        members = Map.put(members, pid, member)
        broadcast(members)
        {:reply, {:ok, slot}, members}
    end
  end

  def handle_call({:mute, muted}, {pid, _}, members) when is_boolean(muted) do
    case members[pid] do
      %{role: role} when role != :listener ->
        members = put_in(members[pid].muted, muted)
        broadcast(members)
        {:reply, :ok, members}

      _ ->
        {:reply, {:error, :unauthorized}, members}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _, _}, members) do
    members = Map.reject(members, fn {_, m} -> m.monitor == ref end)
    broadcast(members)
    if map_size(members) == 0, do: {:stop, :normal, members}, else: {:noreply, members}
  end

  def handle_info(:timeout, members) when map_size(members) == 0, do: {:stop, :normal, members}

  defp broadcast(members) do
    peers = members |> Map.values() |> Enum.sort_by(& &1.slot)
    Enum.each(peers, fn member -> send(member.pid, {:routing, peers}) end)
  end
end
