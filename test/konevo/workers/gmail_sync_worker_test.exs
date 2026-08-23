defmodule Konevo.Workers.GmailSyncWorkerTest do
  use Konevo.DataCase, async: true

  alias Konevo.Inbox.GmailClient
  alias Konevo.Workers.GmailBackfillWorker

  describe "GmailBackfillWorker.build_query/1" do
    test "builds whole-history query" do
      assert {:ok, "-in:trash -in:spam"} = GmailBackfillWorker.build_query(%{"mode" => "all"})
    end

    test "builds since query" do
      assert {:ok, "after:2026/01/01 -in:trash -in:spam"} =
               GmailBackfillWorker.build_query(%{
                 "mode" => "since",
                 "start_date" => "2026-01-01"
               })
    end

    test "builds inclusive between query" do
      assert {:ok, "after:2026/01/01 before:2026/02/01 -in:trash -in:spam"} =
               GmailBackfillWorker.build_query(%{
                 "mode" => "between",
                 "start_date" => "2026-01-01",
                 "end_date" => "2026-01-31"
               })
    end

    test "rejects invalid ranges" do
      assert {:error, :invalid_backfill_range} =
               GmailBackfillWorker.build_query(%{
                 "mode" => "between",
                 "start_date" => "2026-02-01",
                 "end_date" => "2026-01-01"
               })
    end
  end

  describe "token refresh errors" do
    test "detects invalid grants from Google token refresh responses" do
      reason = %{"error" => "invalid_grant", "error_description" => "Bad Request"}

      assert GmailClient.invalid_grant?(reason)
      assert GmailClient.invalid_grant?({:token_refresh_failed, reason})
      refute GmailClient.invalid_grant?(%{"error" => "temporarily_unavailable"})
    end
  end

  # ---------------------------------------------------------------------------
  # Emoji / multi-byte truncation — regression for 0xf0 invalid UTF-8 error.
  #
  # The old truncate used binary_part(str, 0, 250) which slices bytes, creating
  # an incomplete 4-byte UTF-8 sequence like \xf0 at the cut boundary. PostgreSQL
  # rejects this as invalid UTF-8. The fix is String.slice/3 which cuts on
  # codepoint boundaries.
  # ---------------------------------------------------------------------------

  describe "emoji truncation (regression: 0xf0 byte sequence)" do
    test "String.slice produces valid UTF-8 from emoji-heavy strings" do
      # Each flag emoji is multiple bytes. With the old binary_part approach,
      # cutting at byte 250 could land inside a multi-byte sequence.
      # 300 repetitions × 3 graphemes each = 900 grapheme clusters total.
      emoji_str = String.duplicate("🇦🇫❣️🇺🇸", 300)

      truncated = String.slice(emoji_str, 0, 250)

      assert String.valid?(truncated), "truncated string must be valid UTF-8"
      assert String.length(truncated) == 250
    end

    test "String.slice on an exactly-250-char string returns the whole string" do
      str = String.duplicate("a", 250)
      assert String.slice(str, 0, 250) == str
    end

    test "String.slice on a short string returns the whole string" do
      str = "hello 🇦🇫"
      assert String.slice(str, 0, 250) == str
    end

    test "binary_part cuts through multi-byte sequences (demonstrates why it was wrong)" do
      emoji = "🇦🇫"
      assert byte_size(emoji) > 1
      # Cutting at a non-codepoint boundary yields invalid UTF-8
      refute String.valid?(binary_part(emoji, 0, 1))
    end
  end
end
