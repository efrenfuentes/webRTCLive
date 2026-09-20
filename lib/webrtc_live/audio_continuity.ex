defmodule WebRTCLive.AudioContinuity do
  @moduledoc "Keeps an outgoing Opus RTP timeline continuous when a room slot changes owner."

  def rewrite(packet, source, state, now \\ System.monotonic_time(:millisecond))

  def rewrite(packet, source, nil, now) do
    {packet,
     %{
       source: source,
       sequence_offset: 0,
       timestamp_offset: 0,
       sequence: packet.sequence_number,
       timestamp: packet.timestamp,
       last_seen: now
     }}
  end

  def rewrite(packet, source, %{source: previous} = state, now) when source != previous do
    state = %{
      state
      | source: source,
        sequence_offset: state.sequence + 1 - packet.sequence_number,
        timestamp_offset:
          state.timestamp + max(960, (now - state.last_seen) * 48) - packet.timestamp
    }

    rewrite(packet, source, state, now)
  end

  def rewrite(packet, _source, state, now) do
    sequence = Integer.mod(packet.sequence_number + state.sequence_offset, 65_536)
    timestamp = Integer.mod(packet.timestamp + state.timestamp_offset, 4_294_967_296)

    {%{packet | sequence_number: sequence, timestamp: timestamp},
     %{state | sequence: sequence, timestamp: timestamp, last_seen: now}}
  end
end
