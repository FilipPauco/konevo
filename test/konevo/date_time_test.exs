defmodule Konevo.DateTimeTest do
  use ExUnit.Case, async: true

  alias Konevo.DateTime, as: LocalDateTime

  test "formats UTC datetimes in Bratislava summer time" do
    utc = ~U[2026-08-12 21:35:00Z]

    assert LocalDateTime.format_local(utc, "%H:%M") == "23:35"
  end

  test "formats UTC datetimes in Bratislava standard time" do
    utc = ~U[2026-01-12 21:35:00Z]

    assert LocalDateTime.format_local(utc, "%H:%M") == "22:35"
  end
end
