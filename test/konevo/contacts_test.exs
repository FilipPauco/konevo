defmodule Konevo.ContactsTest do
  use Konevo.DataCase, async: true

  import Konevo.Factory
  import Konevo.ContactsFixtures

  alias Konevo.Accounts.Scope
  alias Konevo.Contacts
  alias Konevo.Contacts.Contact

  # Build a fully-wired scope for tests that need an isolated org.
  defp build_scope(role \\ :owner) do
    user = insert(:user)
    org = insert(:organization)
    membership = insert(:membership, user: user, organization: org, role: role)
    Scope.for_user_in_org(user, org, membership)
  end

  setup do
    %{scope: build_scope(:owner)}
  end

  # ---------------------------------------------------------------------------
  # list_contacts/2
  # ---------------------------------------------------------------------------

  describe "list_contacts/2" do
    test "returns contacts scoped to org", %{scope: scope} do
      c1 = contact_fixture(scope, %{first_name: "Alice"})
      c2 = contact_fixture(scope, %{first_name: "Bob"})

      other_scope = build_scope()
      _other = contact_fixture(other_scope, %{first_name: "Hidden"})

      {contacts, total} = Contacts.list_contacts(scope)
      ids = Enum.map(contacts, & &1.id)

      assert c1.id in ids
      assert c2.id in ids
      assert total == 2
    end

    test "does not return another org's contacts", %{scope: scope} do
      other_scope = build_scope()
      other_contact = contact_fixture(other_scope, %{first_name: "Hidden"})

      {contacts, _total} = Contacts.list_contacts(scope)
      ids = Enum.map(contacts, & &1.id)

      refute other_contact.id in ids
    end

    test "filters by search against first_name", %{scope: scope} do
      contact_fixture(scope, %{first_name: "Alice", last_name: "Smith"})
      contact_fixture(scope, %{first_name: "Bob", last_name: "Jones"})

      {contacts, _total} = Contacts.list_contacts(scope, search: "Alice")

      assert length(contacts) == 1
      assert hd(contacts).first_name == "Alice"
    end

    test "filters by search against last_name", %{scope: scope} do
      contact_fixture(scope, %{first_name: "Alice", last_name: "Smith"})
      contact_fixture(scope, %{first_name: "Bob", last_name: "Jones"})

      {contacts, _total} = Contacts.list_contacts(scope, search: "Jones")

      assert length(contacts) == 1
      assert hd(contacts).last_name == "Jones"
    end

    test "filters by status", %{scope: scope} do
      contact_fixture(scope, %{status: :lead})
      contact_fixture(scope, %{status: :customer})
      contact_fixture(scope, %{status: :customer})

      {contacts, total} = Contacts.list_contacts(scope, statuses: [:customer])

      assert total == 2
      assert Enum.all?(contacts, &(&1.status == :customer))
    end

    test "paginates results", %{scope: scope} do
      Enum.each(1..5, fn _ -> contact_fixture(scope) end)

      {page1, total} = Contacts.list_contacts(scope, page: 1, per_page: 2)
      {page2, _} = Contacts.list_contacts(scope, page: 2, per_page: 2)

      assert total == 5
      assert length(page1) == 2
      assert length(page2) == 2
      refute Enum.any?(page1, fn c -> c.id in Enum.map(page2, & &1.id) end)
    end

    test "returns empty list when no contacts", %{scope: scope} do
      {contacts, total} = Contacts.list_contacts(scope)
      assert contacts == []
      assert total == 0
    end
  end

  describe "search_email_recipients/3" do
    test "searches contact emails and company names in the scope", %{scope: scope} do
      company = insert(:company, name: "Acme Labs", user: scope.user, organization: scope.org)

      jane =
        contact_fixture(scope, %{
          first_name: "Jane",
          last_name: "Buyer",
          email: "jane@acme.test",
          company: company
        })

      _no_email =
        contact_fixture(scope, %{
          first_name: "No",
          last_name: "Email",
          email: nil,
          company: company
        })

      other_scope = build_scope()

      hidden_company =
        insert(:company,
          name: "Acme Hidden",
          user: other_scope.user,
          organization: other_scope.org
        )

      _hidden =
        contact_fixture(other_scope, %{
          first_name: "Hidden",
          email: "hidden@acme.test",
          company: hidden_company
        })

      assert {:ok, [result]} = Contacts.search_email_recipients(scope, "acme", 10)
      assert result.id == jane.id
      assert result.company.name == "Acme Labs"
    end
  end

  # ---------------------------------------------------------------------------
  # count_contacts_by_status/1
  # ---------------------------------------------------------------------------

  describe "count_contacts_by_status/1" do
    test "returns a map of status => count scoped to org", %{scope: scope} do
      contact_fixture(scope, %{status: :lead})
      contact_fixture(scope, %{status: :lead})
      contact_fixture(scope, %{status: :customer})

      other_scope = build_scope()
      contact_fixture(other_scope, %{status: :lead})

      counts = Contacts.count_contacts_by_status(scope)

      assert counts[:lead] == 2
      assert counts[:customer] == 1
      refute Map.has_key?(counts, :prospect)
    end
  end

  # ---------------------------------------------------------------------------
  # get_contact!/2
  # ---------------------------------------------------------------------------

  describe "get_contact!/2" do
    test "returns the contact for the correct scope", %{scope: scope} do
      contact = contact_fixture(scope)
      result = Contacts.get_contact!(scope, contact.id)
      assert result.id == contact.id
    end

    test "preloads the company association", %{scope: scope} do
      contact = contact_fixture(scope)
      result = Contacts.get_contact!(scope, contact.id)
      assert %Ecto.Association.NotLoaded{} != result.company
    end

    test "raises when id belongs to another org", %{scope: scope} do
      other_scope = build_scope()
      other_contact = contact_fixture(other_scope)

      assert_raise Ecto.NoResultsError, fn ->
        Contacts.get_contact!(scope, other_contact.id)
      end
    end

    test "raises when id does not exist", %{scope: scope} do
      assert_raise Ecto.NoResultsError, fn ->
        Contacts.get_contact!(scope, -1)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # create_contact/2
  # ---------------------------------------------------------------------------

  describe "create_contact/2" do
    test "creates a contact with valid attrs", %{scope: scope} do
      assert {:ok, %Contact{first_name: "Jane", slug: "jane"}} =
               Contacts.create_contact(scope, %{first_name: "Jane"})
    end

    test "creates a contact with a LinkedIn URL", %{scope: scope} do
      linkedin_url = "https://www.linkedin.com/in/jane-doe"

      assert {:ok, %Contact{linkedin_url: ^linkedin_url}} =
               Contacts.create_contact(scope, %{
                 first_name: "Jane",
                 linkedin_url: linkedin_url
               })
    end

    test "associates the contact with the scope's org and user", %{scope: scope} do
      {:ok, contact} = Contacts.create_contact(scope, %{first_name: "Jane"})
      assert contact.organization_id == scope.org.id
      assert contact.user_id == scope.user.id
    end

    test "returns error changeset when first_name is missing", %{scope: scope} do
      assert {:error, %Ecto.Changeset{}} = Contacts.create_contact(scope, %{})
    end

    test "returns unauthorized for viewer role" do
      scope = build_scope(:viewer)
      assert {:error, :unauthorized} = Contacts.create_contact(scope, %{first_name: "Jane"})
    end

    test "generates duplicate slugs with hyphen suffixes", %{scope: scope} do
      assert {:ok, first} =
               Contacts.create_contact(scope, %{first_name: "Jane", last_name: "Doe"})

      assert {:ok, second} =
               Contacts.create_contact(scope, %{first_name: "Jane", last_name: "Doe"})

      assert first.slug == "jane-doe"
      assert second.slug == "jane-doe-1"
      assert Contacts.get_contact_by_slug_or_id!(scope, second.slug).id == second.id
    end
  end

  describe "find_or_create_by_email/2" do
    test "creates a lead contact from a new email and reuses it", %{scope: scope} do
      assert {:ok, created} = Contacts.find_or_create_by_email(scope, "Martin.Smith@example.com")
      assert created.email == "martin.smith@example.com"
      assert created.first_name == "Martin"
      assert created.status == :lead

      assert {:ok, existing} = Contacts.find_or_create_by_email(scope, "MARTIN.SMITH@example.com")
      assert existing.id == created.id
    end

    test "rejects an invalid email", %{scope: scope} do
      assert {:error, :invalid_email} = Contacts.find_or_create_by_email(scope, "not-an-email")
    end
  end

  # ---------------------------------------------------------------------------
  # update_contact/3
  # ---------------------------------------------------------------------------

  describe "update_contact/3" do
    test "updates with valid attrs", %{scope: scope} do
      contact = contact_fixture(scope)
      assert {:ok, updated} = Contacts.update_contact(scope, contact, %{first_name: "Updated"})
      assert updated.first_name == "Updated"
      assert updated.slug == "updated-last"
    end

    test "updates the LinkedIn URL", %{scope: scope} do
      contact = contact_fixture(scope)
      linkedin_url = "https://www.linkedin.com/in/updated-contact"

      assert {:ok, updated} =
               Contacts.update_contact(scope, contact, %{linkedin_url: linkedin_url})

      assert updated.linkedin_url == linkedin_url
    end

    test "returns error changeset for invalid attrs", %{scope: scope} do
      contact = contact_fixture(scope)

      assert {:error, %Ecto.Changeset{}} =
               Contacts.update_contact(scope, contact, %{first_name: ""})
    end

    test "returns unauthorized for viewer role", %{scope: owner_scope} do
      contact = contact_fixture(owner_scope)

      viewer = insert(:user)

      viewer_membership =
        insert(:membership, user: viewer, organization: owner_scope.org, role: :viewer)

      viewer_scope = Scope.for_user_in_org(viewer, owner_scope.org, viewer_membership)

      assert {:error, :unauthorized} =
               Contacts.update_contact(viewer_scope, contact, %{first_name: "Hacked"})
    end
  end

  # ---------------------------------------------------------------------------
  # delete_contact/2
  # ---------------------------------------------------------------------------

  describe "delete_contact/2" do
    test "deletes for owner", %{scope: scope} do
      contact = contact_fixture(scope)
      assert {:ok, _deleted} = Contacts.delete_contact(scope, contact)

      assert_raise Ecto.NoResultsError, fn ->
        Contacts.get_contact!(scope, contact.id)
      end
    end

    test "returns unauthorized for member role", %{scope: owner_scope} do
      contact = contact_fixture(owner_scope)

      member = insert(:user)

      member_membership =
        insert(:membership, user: member, organization: owner_scope.org, role: :member)

      member_scope = Scope.for_user_in_org(member, owner_scope.org, member_membership)

      assert {:error, :unauthorized} = Contacts.delete_contact(member_scope, contact)
    end
  end

  # ---------------------------------------------------------------------------
  # change_contact/2
  # ---------------------------------------------------------------------------

  describe "change_contact/2" do
    test "returns a changeset", %{scope: scope} do
      contact = contact_fixture(scope)
      assert %Ecto.Changeset{} = Contacts.change_contact(contact)
    end

    test "changeset reflects provided attrs", %{scope: scope} do
      contact = contact_fixture(scope)
      changeset = Contacts.change_contact(contact, %{first_name: "Draft"})
      assert Ecto.Changeset.get_field(changeset, :first_name) == "Draft"
    end
  end

  # ---------------------------------------------------------------------------
  # Contact.changeset/2 — schema-level validations
  # ---------------------------------------------------------------------------

  describe "Contact.changeset/2" do
    test "requires first_name" do
      changeset = Contact.changeset(%Contact{}, %{})
      assert "can't be blank" in errors_on(changeset).first_name
    end

    test "validates email format" do
      changeset = Contact.changeset(%Contact{}, %{first_name: "Jane", email: "not-an-email"})
      assert "must be a valid email" in errors_on(changeset).email
    end

    test "accepts a blank email (optional field)" do
      changeset = Contact.changeset(%Contact{}, %{first_name: "Jane"})
      refute Map.has_key?(errors_on(changeset), :email)
    end

    test "validates LinkedIn URL format" do
      changeset =
        Contact.changeset(%Contact{}, %{first_name: "Jane", linkedin_url: "example.com"})

      assert "must be a valid LinkedIn URL" in errors_on(changeset).linkedin_url
    end

    test "rejects an invalid status" do
      changeset = Contact.changeset(%Contact{}, %{first_name: "Jane", status: :ghost})
      assert errors_on(changeset).status != []
    end

    test "accepts all valid statuses" do
      for status <- [:lead, :prospect, :customer, :churned] do
        changeset = Contact.changeset(%Contact{}, %{first_name: "Jane", status: status})
        assert changeset.valid?
      end
    end

    test "rejects first_name longer than 255 chars" do
      changeset = Contact.changeset(%Contact{}, %{first_name: String.duplicate("a", 256)})
      assert "should be at most 255 character(s)" in errors_on(changeset).first_name
    end
  end
end
