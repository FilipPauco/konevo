defmodule Konevo.SupportTest do
  use Konevo.DataCase, async: false

  import Konevo.AccountsFixtures

  alias Konevo.Support

  describe "deliver_support_request/2" do
    test "requires the configured global support Gmail integration" do
      %{scope: scope} = user_with_org_fixture()

      assert {:error, :support_gmail_not_connected} =
               Support.deliver_support_request(scope, %{
                 "topic" => "bug",
                 "subject" => "Calendar sync issue",
                 "message" => "The calendar sync button does not finish loading."
               })
    end

    test "returns validation errors for invalid input" do
      %{scope: scope} = user_with_org_fixture()

      assert {:error, changeset} =
               Support.deliver_support_request(scope, %{
                 "topic" => "bug",
                 "subject" => "",
                 "message" => "short"
               })

      refute changeset.valid?
      assert %{subject: [_], message: [_]} = errors_on(changeset)
    end
  end
end
