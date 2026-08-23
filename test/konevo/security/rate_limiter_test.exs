defmodule Konevo.Security.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Konevo.Security.RateLimiter

  setup do
    RateLimiter.reset!()
    on_exit(fn -> RateLimiter.reset!() end)
  end

  test "limits repeated public landing connections from one client" do
    for _ <- 1..30 do
      assert :ok = RateLimiter.check(:public_landing, ip: "203.0.113.42")
    end

    assert {:error, _retry_after} = RateLimiter.check(:public_landing, ip: "203.0.113.42")
    assert :ok = RateLimiter.check(:public_landing, ip: "203.0.113.43")
  end
end
