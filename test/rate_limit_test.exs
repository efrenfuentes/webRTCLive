defmodule WebRTCLive.RateLimitTest do
  use ExUnit.Case, async: true

  test "rejects requests above the limit and keeps keys independent" do
    key = {:test, make_ref()}
    assert WebRTCLive.RateLimit.allow?(key, 1)
    refute WebRTCLive.RateLimit.allow?(key, 1)
    assert WebRTCLive.RateLimit.allow?({:test, make_ref()}, 1)
  end
end
