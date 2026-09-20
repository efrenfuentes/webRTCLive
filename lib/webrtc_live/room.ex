defmodule WebRTCLive.Room do
  @moduledoc "An ephemeral audio relay room with one publisher and one listener."
  use GenServer, restart: :temporary

  def start_link(name), do: GenServer.start_link(__MODULE__, name, name: via(name))
  defp via(name), do: {:via, Registry, {WebRTCLive.Registry, name}}

  def get_or_start(name) do
    case DynamicSupervisor.start_child(WebRTCLive.RoomSupervisor, {__MODULE__, name}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  def join(room, role, peer), do: GenServer.call(room, {:join, role, peer})

  @impl true
  def init(_name), do: {:ok, %{}, 30_000}

  @impl true
  def handle_call({:join, role, peer}, {pid, _}, members) do
    if Map.has_key?(members, role) do
      {:reply, {:error, :role_taken}, members}
    else
      member = Map.merge(peer, %{pid: pid, monitor: Process.monitor(pid)})
      members = Map.put(members, role, member)

      if publisher = members[:publisher] do
        send(publisher.pid, {:destination, members[:listener]})
      end

      Enum.each(members, fn {_, member} -> send(member.pid, {:members, Map.keys(members)}) end)
      {:reply, :ok, members}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _, _}, members) do
    {departed, remaining} = Enum.split_with(members, fn {_, m} -> m.monitor == ref end)
    members = Map.new(remaining)

    if Keyword.has_key?(departed, :publisher) do
      Enum.each(members, fn {_, m} -> send(m.pid, :publisher_left) end)
    else
      if publisher = members[:publisher], do: send(publisher.pid, {:destination, nil})
    end

    Enum.each(members, fn {_, m} -> send(m.pid, {:members, Map.keys(members)}) end)
    if map_size(members) == 0, do: {:stop, :normal, members}, else: {:noreply, members}
  end

  def handle_info(:timeout, members) when map_size(members) == 0, do: {:stop, :normal, members}
end
