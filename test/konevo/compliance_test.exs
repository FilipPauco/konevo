defmodule Konevo.ComplianceTest do
  use Konevo.DataCase, async: true

  import Konevo.Factory

  alias Konevo.Accounts.Scope
  alias Konevo.Compliance
  alias Konevo.Compliance.{AuditLog, Consent, SuppressionEntry}

  defp build_scope(role \\ :owner) do
    user = insert(:user)
    org = insert(:organization)
    membership = insert(:membership, user: user, organization: org, role: role)
    Scope.for_user_in_org(user, org, membership)
  end

  defp contact_for(scope) do
    insert(:contact, organization: scope.org, user: scope.user)
  end

  # ---------------------------------------------------------------------------
  # has_consent?/2
  # ---------------------------------------------------------------------------

  describe "has_consent?/2" do
    test "returns false when no consent record exists" do
      scope = build_scope()
      contact = contact_for(scope)

      refute Compliance.has_consent?(contact, :email)
    end

    test "returns true for a granted consent" do
      scope = build_scope()
      contact = contact_for(scope)

      insert(:consent,
        contact: contact,
        organization: scope.org,
        channel: :email,
        status: :granted
      )

      assert Compliance.has_consent?(contact, :email)
    end

    test "returns false for a revoked consent" do
      scope = build_scope()
      contact = contact_for(scope)

      insert(:consent,
        contact: contact,
        organization: scope.org,
        channel: :email,
        status: :revoked
      )

      refute Compliance.has_consent?(contact, :email)
    end

    test "is channel-specific" do
      scope = build_scope()
      contact = contact_for(scope)

      insert(:consent,
        contact: contact,
        organization: scope.org,
        channel: :email,
        status: :granted
      )

      refute Compliance.has_consent?(contact, :sms)
    end
  end

  # ---------------------------------------------------------------------------
  # record_consent/4
  # ---------------------------------------------------------------------------

  describe "record_consent/4" do
    test "creates a new consent record" do
      scope = build_scope()
      contact = contact_for(scope)

      assert {:ok, %Consent{status: :granted, channel: :email}} =
               Compliance.record_consent(contact, :email, :manual)
    end

    test "stores ip_address when provided" do
      scope = build_scope()
      contact = contact_for(scope)

      {:ok, consent} = Compliance.record_consent(contact, :email, :form, "1.2.3.4")
      assert consent.ip_address == "1.2.3.4"
      assert consent.source == :form
    end

    test "sets granted_at timestamp" do
      scope = build_scope()
      contact = contact_for(scope)

      {:ok, consent} = Compliance.record_consent(contact, :email, :manual)
      assert consent.granted_at != nil
    end

    test "upserts — updates existing record instead of creating duplicate" do
      scope = build_scope()
      contact = contact_for(scope)

      {:ok, _first} = Compliance.record_consent(contact, :email, :import)
      {:ok, second} = Compliance.record_consent(contact, :email, :form)

      all = Compliance.list_consents(contact)
      assert length(all) == 1
      assert hd(all).source == :form
      assert second.status == :granted
    end

    test "re-grants a previously revoked consent" do
      scope = build_scope()
      contact = contact_for(scope)

      {:ok, consent} = Compliance.record_consent(contact, :email, :manual)
      Compliance.revoke_consent(contact, :email)
      {:ok, re_granted} = Compliance.record_consent(contact, :email, :form)

      assert re_granted.id == consent.id
      assert re_granted.status == :granted
    end
  end

  # ---------------------------------------------------------------------------
  # revoke_consent/2
  # ---------------------------------------------------------------------------

  describe "revoke_consent/2" do
    test "marks consent as revoked" do
      scope = build_scope()
      contact = contact_for(scope)

      Compliance.record_consent(contact, :email, :manual)
      {:ok, revoked} = Compliance.revoke_consent(contact, :email)

      assert revoked.status == :revoked
      assert revoked.revoked_at != nil
    end

    test "returns {:ok, nil} when no consent record exists" do
      scope = build_scope()
      contact = contact_for(scope)

      assert {:ok, nil} = Compliance.revoke_consent(contact, :sms)
    end
  end

  # ---------------------------------------------------------------------------
  # list_consents/1
  # ---------------------------------------------------------------------------

  describe "list_consents/1" do
    test "returns all consents for a contact across channels" do
      scope = build_scope()
      contact = contact_for(scope)

      Compliance.record_consent(contact, :email, :manual)
      Compliance.record_consent(contact, :sms, :form)

      consents = Compliance.list_consents(contact)
      channels = Enum.map(consents, & &1.channel)

      assert :email in channels
      assert :sms in channels
    end

    test "does not return consents for other contacts" do
      scope = build_scope()
      contact1 = contact_for(scope)
      contact2 = contact_for(scope)

      Compliance.record_consent(contact1, :email, :manual)

      assert Compliance.list_consents(contact2) == []
    end
  end

  # ---------------------------------------------------------------------------
  # suppressed?/3
  # ---------------------------------------------------------------------------

  describe "suppressed?/3" do
    test "returns false when not suppressed" do
      scope = build_scope()
      refute Compliance.suppressed?(scope.org, :email, "clean@example.com")
    end

    test "returns true after suppress/5" do
      scope = build_scope()
      Compliance.suppress(scope.org, :email, "bad@example.com", :bounced)

      assert Compliance.suppressed?(scope.org, :email, "bad@example.com")
    end

    test "is channel-specific" do
      scope = build_scope()
      Compliance.suppress(scope.org, :email, "test@example.com", :unsubscribed)

      refute Compliance.suppressed?(scope.org, :sms, "test@example.com")
    end

    test "is org-scoped" do
      scope1 = build_scope()
      scope2 = build_scope()
      Compliance.suppress(scope1.org, :email, "shared@example.com", :manual)

      refute Compliance.suppressed?(scope2.org, :email, "shared@example.com")
    end
  end

  # ---------------------------------------------------------------------------
  # suppress/5
  # ---------------------------------------------------------------------------

  describe "suppress/5" do
    test "creates a suppression entry" do
      scope = build_scope()

      assert {:ok, %SuppressionEntry{reason: :bounced}} =
               Compliance.suppress(scope.org, :email, "bounce@example.com", :bounced)
    end

    test "returns error on duplicate (already suppressed)" do
      scope = build_scope()
      Compliance.suppress(scope.org, :email, "dup@example.com", :bounced)

      assert {:error, changeset} =
               Compliance.suppress(scope.org, :email, "dup@example.com", :manual)

      assert "already suppressed" in errors_on(changeset).organization_id
    end

    test "accepts optional source_message" do
      scope = build_scope()

      msg =
        insert(:message_sent,
          organization: scope.org,
          sent_by: scope.user,
          recipient: "msg@example.com"
        )

      {:ok, entry} =
        Compliance.suppress(scope.org, :email, "msg@example.com", :bounced, msg)

      assert entry.source_message_id == msg.id
    end
  end

  # ---------------------------------------------------------------------------
  # unsuppress/3
  # ---------------------------------------------------------------------------

  describe "unsuppress/3" do
    test "removes the suppression entry" do
      scope = build_scope()
      Compliance.suppress(scope.org, :email, "remove@example.com", :manual)

      assert :ok = Compliance.unsuppress(scope.org, :email, "remove@example.com")
      refute Compliance.suppressed?(scope.org, :email, "remove@example.com")
    end

    test "is a no-op when entry does not exist" do
      scope = build_scope()
      assert :ok = Compliance.unsuppress(scope.org, :email, "nonexistent@example.com")
    end
  end

  # ---------------------------------------------------------------------------
  # list_suppressed/2
  # ---------------------------------------------------------------------------

  describe "list_suppressed/2" do
    test "returns all suppression entries for org" do
      scope = build_scope()
      Compliance.suppress(scope.org, :email, "a@example.com", :bounced)
      Compliance.suppress(scope.org, :sms, "+15551234567", :unsubscribed)

      entries = Compliance.list_suppressed(scope.org)
      assert length(entries) == 2
    end

    test "filters by channel" do
      scope = build_scope()
      Compliance.suppress(scope.org, :email, "b@example.com", :bounced)
      Compliance.suppress(scope.org, :sms, "+15559876543", :manual)

      email_entries = Compliance.list_suppressed(scope.org, channel: :email)
      assert length(email_entries) == 1
      assert hd(email_entries).channel == :email
    end

    test "does not include other orgs" do
      scope1 = build_scope()
      scope2 = build_scope()
      Compliance.suppress(scope1.org, :email, "org1@example.com", :bounced)

      assert Compliance.list_suppressed(scope2.org) == []
    end
  end

  # ---------------------------------------------------------------------------
  # check_sendable/3
  # ---------------------------------------------------------------------------

  describe "check_sendable/3" do
    test "returns :ok when consent granted and not suppressed" do
      scope = build_scope()

      contact =
        insert(:contact, organization: scope.org, user: scope.user, email: "ok@example.com")

      Compliance.record_consent(contact, :email, :manual)

      assert :ok = Compliance.check_sendable(scope.org, contact, :email)
    end

    test "returns {:error, :no_consent} when no consent" do
      scope = build_scope()

      contact =
        insert(:contact, organization: scope.org, user: scope.user, email: "nc@example.com")

      assert {:error, :no_consent} = Compliance.check_sendable(scope.org, contact, :email)
    end

    test "returns {:error, :suppressed} when value is suppressed" do
      scope = build_scope()

      contact =
        insert(:contact, organization: scope.org, user: scope.user, email: "sup@example.com")

      Compliance.record_consent(contact, :email, :manual)
      Compliance.suppress(scope.org, :email, "sup@example.com", :bounced)

      assert {:error, :suppressed} = Compliance.check_sendable(scope.org, contact, :email)
    end

    test "returns {:error, :no_address} for sms with no phone" do
      scope = build_scope()
      contact = insert(:contact, organization: scope.org, user: scope.user, phone: nil)

      assert {:error, :no_address} = Compliance.check_sendable(scope.org, contact, :sms)
    end
  end

  # ---------------------------------------------------------------------------
  # unsubscribe/4
  # ---------------------------------------------------------------------------

  describe "unsubscribe/4" do
    test "revokes consent and suppresses in one transaction" do
      scope = build_scope()

      contact =
        insert(:contact, organization: scope.org, user: scope.user, email: "unsub@example.com")

      Compliance.record_consent(contact, :email, :manual)

      assert {:ok, _} = Compliance.unsubscribe(scope.org, contact, :email)

      refute Compliance.has_consent?(contact, :email)
      assert Compliance.suppressed?(scope.org, :email, "unsub@example.com")
    end
  end

  # ---------------------------------------------------------------------------
  # log_action/4
  # ---------------------------------------------------------------------------

  describe "log_action/4" do
    test "creates an audit log entry" do
      scope = build_scope()

      assert {:ok, %AuditLog{action: "contact.created"}} =
               Compliance.log_action(scope.org, "contact.created", scope.user,
                 resource_type: "contact",
                 resource_id: 42
               )
    end

    test "allows nil actor for system actions" do
      scope = build_scope()

      assert {:ok, %AuditLog{actor_id: nil}} =
               Compliance.log_action(scope.org, "system.sync", nil)
    end

    test "stores metadata map" do
      scope = build_scope()

      {:ok, log} =
        Compliance.log_action(scope.org, "deal.stage_changed", scope.user,
          metadata: %{from: "Qualified", to: "Proposal Sent"}
        )

      assert log.metadata == %{from: "Qualified", to: "Proposal Sent"}
    end

    test "stores ip_address" do
      scope = build_scope()

      {:ok, log} =
        Compliance.log_action(scope.org, "user.login", scope.user, ip_address: "10.0.0.1")

      assert log.ip_address == "10.0.0.1"
    end
  end

  # ---------------------------------------------------------------------------
  # list_audit_logs/2
  # ---------------------------------------------------------------------------

  describe "list_audit_logs/2" do
    test "returns logs for org newest first" do
      scope = build_scope()
      Compliance.log_action(scope.org, "contact.created", scope.user)
      Compliance.log_action(scope.org, "deal.created", scope.user)

      logs = Compliance.list_audit_logs(scope.org)
      assert length(logs) >= 2
    end

    test "does not return other org logs" do
      scope1 = build_scope()
      scope2 = build_scope()
      Compliance.log_action(scope1.org, "contact.created", scope1.user)

      assert Compliance.list_audit_logs(scope2.org) == []
    end

    test "filters by action" do
      scope = build_scope()
      Compliance.log_action(scope.org, "contact.created", scope.user)
      Compliance.log_action(scope.org, "deal.created", scope.user)

      logs = Compliance.list_audit_logs(scope.org, action: "contact.created")
      assert Enum.all?(logs, &(&1.action == "contact.created"))
    end

    test "filters by resource_type and resource_id" do
      scope = build_scope()

      Compliance.log_action(scope.org, "contact.updated", scope.user,
        resource_type: "contact",
        resource_id: 99
      )

      Compliance.log_action(scope.org, "contact.updated", scope.user,
        resource_type: "contact",
        resource_id: 88
      )

      logs =
        Compliance.list_audit_logs(scope.org, resource_type: "contact", resource_id: 99)

      assert length(logs) == 1
      assert hd(logs).resource_id == 99
    end

    test "filters by actor_id" do
      scope = build_scope()
      other_user = insert(:user)
      Compliance.log_action(scope.org, "contact.created", scope.user)
      Compliance.log_action(scope.org, "deal.created", other_user)

      logs = Compliance.list_audit_logs(scope.org, actor_id: scope.user.id)
      assert Enum.all?(logs, &(&1.actor_id == scope.user.id))
    end

    test "respects limit option" do
      scope = build_scope()
      Enum.each(1..5, fn _ -> Compliance.log_action(scope.org, "ping", scope.user) end)

      logs = Compliance.list_audit_logs(scope.org, limit: 3)
      assert length(logs) == 3
    end
  end

  # ---------------------------------------------------------------------------
  # Schema validations
  # ---------------------------------------------------------------------------

  describe "Consent.changeset/2" do
    test "requires channel" do
      cs = Consent.changeset(%Consent{}, %{})
      assert "can't be blank" in errors_on(cs).channel
    end
  end

  describe "SuppressionEntry.changeset/2" do
    test "requires channel and value" do
      cs = SuppressionEntry.changeset(%SuppressionEntry{}, %{})
      errors = errors_on(cs)
      assert "can't be blank" in errors.channel
      assert "can't be blank" in errors.value
    end
  end

  describe "AuditLog.changeset/2" do
    test "requires action" do
      cs = AuditLog.changeset(%AuditLog{}, %{})
      assert "can't be blank" in errors_on(cs).action
    end
  end
end
