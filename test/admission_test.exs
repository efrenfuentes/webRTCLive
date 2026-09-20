defmodule WebRTCLive.AdmissionTest do
  use ExUnit.Case, async: true
  alias WebRTCLive.Admission

  test "capacity is atomic and reservations are released on owner death" do
    server = start_supervised!({Admission, name: nil, limit: 1})
    parent = self()

    owner =
      spawn(fn ->
        send(parent, {:acquired, Admission.acquire(server)})

        receive do
          :finish -> :ok
        end
      end)

    assert_receive {:acquired, :ok}
    assert {:error, :capacity_reached} = Admission.acquire(server)
    monitor = Process.monitor(owner)
    send(owner, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^owner, _}
    eventually_acquire(server, 50)
    assert :ok = Admission.acquire(server)
    assert :ok = Admission.release(server)
    assert :ok = Admission.acquire(server)
  end

  defp eventually_acquire(server, attempts) do
    case Admission.acquire(server) do
      :ok ->
        :ok

      _ when attempts > 0 ->
        Process.sleep(10)
        eventually_acquire(server, attempts - 1)

      other ->
        flunk("Capacity not released: #{inspect(other)}")
    end
  end
end
