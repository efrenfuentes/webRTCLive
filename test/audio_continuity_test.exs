defmodule WebRTCLive.AudioContinuityTest do
  use ExUnit.Case, async: true
  alias WebRTCLive.AudioContinuity

  test "slot reuse continues sequence and timestamps, including wraparound" do
    first = ExRTP.Packet.new(<<1>>, sequence_number: 65_535, timestamp: 4_294_967_000)
    {^first, state} = AudioContinuity.rewrite(first, :alice, nil, 0)
    packet = ExRTP.Packet.new(<<2>>, sequence_number: 500, timestamp: 9000)
    {rewritten, state} = AudioContinuity.rewrite(packet, :bob, state, 20)
    assert rewritten.sequence_number == 0
    assert rewritten.timestamp == 664
    next = %{packet | sequence_number: 502, timestamp: 10_920}
    {rewritten, _} = AudioContinuity.rewrite(next, :bob, state)
    assert rewritten.sequence_number == 2
    assert rewritten.timestamp == 2584
    assert rewritten.payload == <<2>>
  end

  test "timestamp accounts for silence while a slot is empty" do
    first = ExRTP.Packet.new(<<1>>, sequence_number: 10, timestamp: 1000)
    {_, state} = AudioContinuity.rewrite(first, :alice, nil, 0)
    replacement = ExRTP.Packet.new(<<2>>, sequence_number: 50, timestamp: 9000)
    {packet, _} = AudioContinuity.rewrite(replacement, :bob, state, 2000)
    assert packet.sequence_number == 11
    assert packet.timestamp == 97_000
  end
end
