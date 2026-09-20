defmodule WebRTCLive.RoomTest do
  use ExUnit.Case, async: true
  alias WebRTCLive.Room

  defp member(room, identity, role \\ :participant) do
    parent = self()

    pid =
      spawn(fn ->
        send(parent, {:joined, self(), Room.join(room, role, %{identity: identity})})

        receive do
          :leave -> :ok
        end
      end)

    on_exit(fn -> Process.exit(pid, :kill) end)
    assert_receive {:joined, ^pid, result}
    {pid, result}
  end

  test "four unique slots, identity checks, capacity, and slot reuse" do
    {:ok, room} = Room.get_or_start("room-#{System.unique_integer([:positive])}")
    assert {:ok, 0} = Room.join(room, :participant, %{identity: "alice"})
    assert {_, {:error, :identity_taken}} = member(room, "alice")
    assert {bob, {:ok, 1}} = member(room, "bob")
    assert {_, {:ok, 2}} = member(room, "carol")
    assert {_, {:ok, 3}} = member(room, "dave")
    assert {_, {:error, :room_full}} = member(room, "eve")
    send(bob, :leave)
    assert_receive {:routing, [%{identity: "alice"}, %{identity: "carol"}, %{identity: "dave"}]}
    assert {_, {:ok, 1}} = member(room, "eve")
    assert Process.alive?(room)
    assert :ok = Room.mute(room, true)
    assert_receive {:routing, [%{identity: "alice", muted: true} | _]}
  end

  test "empty rooms disappear after their last participant exits" do
    {:ok, room} = Room.get_or_start("cleanup-#{System.unique_integer([:positive])}")
    ref = Process.monitor(room)
    {participant, {:ok, 0}} = member(room, "alice")
    send(participant, :leave)
    assert_receive {:DOWN, ^ref, :process, ^room, :normal}
  end

  test "concurrent room creation resolves to the same process" do
    name = "concurrent-#{System.unique_integer([:positive])}"
    results = 1..10 |> Task.async_stream(fn _ -> Room.get_or_start(name) end) |> Enum.to_list()
    assert [{:ok, {:ok, room}}] = Enum.uniq(results)
    GenServer.stop(room)
  end

  test "room cap rejects new rooms but permits joining an existing room" do
    supervisor = start_supervised!({DynamicSupervisor, strategy: :one_for_one, max_children: 1})
    name = "limited-#{System.unique_integer([:positive])}"
    assert {:ok, room} = Room.get_or_start(name, supervisor)
    assert {:ok, ^room} = Room.get_or_start(name, supervisor)
    assert {:error, :max_children} = Room.get_or_start(name <> "-extra", supervisor)
  end
end
