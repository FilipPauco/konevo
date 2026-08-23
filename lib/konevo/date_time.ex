defmodule Konevo.DateTime do
  @moduledoc false

  @local_zone "Europe/Bratislava"
  @standard_offset 3_600
  @summer_offset 7_200

  def local_zone, do: @local_zone

  def local_today do
    DateTime.utc_now(:second)
    |> to_local_naive()
    |> NaiveDateTime.to_date()
  end

  def from_local_naive!(%NaiveDateTime{} = naive) do
    naive
    |> NaiveDateTime.add(-local_offset(naive), :second)
    |> DateTime.from_naive!("Etc/UTC")
  end

  def to_local_naive(%DateTime{} = datetime) do
    utc = DateTime.shift_zone!(datetime, "Etc/UTC")

    utc
    |> DateTime.add(utc_offset(utc), :second)
    |> DateTime.to_naive()
  end

  def format_local(%DateTime{} = datetime, format) do
    datetime
    |> to_local_naive()
    |> Calendar.strftime(format)
  end

  defp local_offset(%NaiveDateTime{} = naive) do
    year = naive.year
    summer_start = NaiveDateTime.new!(last_sunday(year, 3), ~T[02:00:00])
    summer_end = NaiveDateTime.new!(last_sunday(year, 10), ~T[03:00:00])

    if NaiveDateTime.compare(naive, summer_start) in [:eq, :gt] and
         NaiveDateTime.compare(naive, summer_end) == :lt do
      @summer_offset
    else
      @standard_offset
    end
  end

  defp utc_offset(%DateTime{} = utc) do
    year = utc.year
    summer_start = DateTime.new!(last_sunday(year, 3), ~T[01:00:00], "Etc/UTC")
    summer_end = DateTime.new!(last_sunday(year, 10), ~T[01:00:00], "Etc/UTC")

    if DateTime.compare(utc, summer_start) in [:eq, :gt] and
         DateTime.compare(utc, summer_end) == :lt do
      @summer_offset
    else
      @standard_offset
    end
  end

  defp last_sunday(year, month) do
    date = Date.end_of_month(Date.new!(year, month, 1))
    Date.add(date, -rem(Date.day_of_week(date), 7))
  end
end
