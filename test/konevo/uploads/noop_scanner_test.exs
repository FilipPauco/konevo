defmodule Konevo.Uploads.NoopScannerTest do
  use ExUnit.Case, async: true

  alias Konevo.Uploads.NoopScanner

  describe "scan/1" do
    test "always returns :clean" do
      assert NoopScanner.scan("/any/file/path") == :clean
      assert NoopScanner.scan("") == :clean
      assert NoopScanner.scan("file.jpg") == :clean
    end

    test "logs that scanning is disabled" do
      # The function logs a warning - we just verify it doesn't crash
      assert NoopScanner.scan("/test/file.pdf") == :clean
    end
  end
end
