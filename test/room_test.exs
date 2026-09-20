defmodule WebRTCLive.RoomTest do
  use ExUnit.Case, async: true
  alias WebRTCLive.Room

  test "routes publisher directly to listener and rejects duplicate roles" do
    {:ok, room} = Room.get_or_start("room-#{System.unique_integer([:positive])}")
    assert :ok = Room.join(room, :publisher, %{pc: self(), track: 1})
    assert_receive {:destination, nil}
    assert {:error, :role_taken} = Room.join(room, :publisher, %{pc: self(), track: 2})
    parent = self()

    listener =
      spawn(fn ->
        :ok = Room.join(room, :listener, %{pc: parent, track: 3})
        send(parent, :joined)

        receive do
          :leave -> :ok
        end
      end)

    assert_receive :joined
    assert_receive {:destination, %{pid: ^listener, track: 3}}
    send(listener, :leave)
    assert_receive {:destination, nil}
    assert_receive {:members, [:publisher]}
  end

  test "empty rooms disappear after their last participant exits" do
    name = "cleanup-#{System.unique_integer([:positive])}"
    {:ok, room} = Room.get_or_start(name)
    ref = Process.monitor(room)
    parent = self()

    participant =
      spawn(fn ->
        :ok = Room.join(room, :publisher, %{pc: self(), track: 1})
        send(parent, :joined)

        receive do
          :leave -> :ok
        end
      end)

    assert_receive :joined
    send(participant, :leave)
    assert_receive {:DOWN, ^ref, :process, ^room, :normal}
    # Registry processes the same DOWN asynchronously; room exit is immediate.
    assert_registry_empty(name, 50)
  end

  test "concurrent room creation resolves to the same process" do
    name = "concurrent-#{System.unique_integer([:positive])}"
    results = 1..10 |> Task.async_stream(fn _ -> Room.get_or_start(name) end) |> Enum.to_list()
    assert [{:ok, {:ok, room}}] = Enum.uniq(results)
    GenServer.stop(room)
  end

  defp assert_registry_empty(name, attempts) do
    case Registry.lookup(WebRTCLive.Registry, name) do
      [] ->
        :ok

      _ when attempts > 0 ->
        Process.sleep(10)
        assert_registry_empty(name, attempts - 1)

      remaining ->
        flunk("Room still registered: #{inspect(remaining)}")
    end
  end
end
