defmodule Konevo.Contacts.NotesTest do
  use Konevo.DataCase, async: true

  import Konevo.Factory
  import Konevo.ContactsFixtures

  alias Konevo.Accounts.Scope
  alias Konevo.Contacts
  alias Konevo.Contacts.Note

  defp build_scope(role \\ :owner) do
    user = insert(:user)
    org = insert(:organization)
    membership = insert(:membership, user: user, organization: org, role: role)
    Scope.for_user_in_org(user, org, membership)
  end

  setup do
    scope = build_scope(:owner)
    contact = contact_fixture(scope)
    %{scope: scope, contact: contact}
  end

  # ---------------------------------------------------------------------------
  # add_note/3
  # ---------------------------------------------------------------------------

  describe "add_note/3" do
    test "creates a note linked to contact and org", %{scope: scope, contact: contact} do
      assert {:ok, %Note{body: "Great lead."}} =
               Contacts.add_note(scope, contact, %{body: "Great lead."})
    end

    test "associates note with created_by user", %{scope: scope, contact: contact} do
      {:ok, note} = Contacts.add_note(scope, contact, %{body: "Follow up."})
      assert note.created_by_id == scope.user.id
      assert note.organization_id == scope.org.id
      assert note.contact_id == contact.id
    end

    test "returns error changeset when body is blank", %{scope: scope, contact: contact} do
      assert {:error, %Ecto.Changeset{}} = Contacts.add_note(scope, contact, %{body: ""})
    end

    test "returns unauthorized for viewer" do
      scope = build_scope(:viewer)
      contact = contact_fixture(build_scope())
      assert {:error, :unauthorized} = Contacts.add_note(scope, contact, %{body: "X"})
    end
  end

  # ---------------------------------------------------------------------------
  # list_notes/2
  # ---------------------------------------------------------------------------

  describe "list_notes/2" do
    test "returns notes for the contact ordered newest first", %{scope: scope, contact: contact} do
      {:ok, n1} = Contacts.add_note(scope, contact, %{body: "First"})
      {:ok, n2} = Contacts.add_note(scope, contact, %{body: "Second"})

      {:ok, notes} = Contacts.list_notes(scope, contact)
      ids = Enum.map(notes, & &1.id)

      assert n1.id in ids
      assert n2.id in ids
    end

    test "returns notes for viewer (read is permitted)", %{scope: scope, contact: contact} do
      {:ok, _note} = Contacts.add_note(scope, contact, %{body: "Visible"})

      viewer = insert(:user)
      membership = insert(:membership, user: viewer, organization: scope.org, role: :viewer)
      viewer_scope = Scope.for_user_in_org(viewer, scope.org, membership)

      assert {:ok, notes} = Contacts.list_notes(viewer_scope, contact)
      assert length(notes) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # update_note/3
  # ---------------------------------------------------------------------------

  describe "update_note/3" do
    test "creator can update their own note", %{scope: scope, contact: contact} do
      {:ok, note} = Contacts.add_note(scope, contact, %{body: "Original"})
      assert {:ok, updated} = Contacts.update_note(scope, note, %{body: "Revised"})
      assert updated.body == "Revised"
    end

    test "another user cannot update the note", %{scope: owner_scope, contact: contact} do
      {:ok, note} = Contacts.add_note(owner_scope, contact, %{body: "Original"})

      other = insert(:user)
      membership = insert(:membership, user: other, organization: owner_scope.org, role: :member)
      other_scope = Scope.for_user_in_org(other, owner_scope.org, membership)

      assert {:error, :unauthorized} = Contacts.update_note(other_scope, note, %{body: "Hacked"})
    end
  end

  # ---------------------------------------------------------------------------
  # delete_note/2
  # ---------------------------------------------------------------------------

  describe "delete_note/2" do
    test "deletes note for owner", %{scope: scope, contact: contact} do
      {:ok, note} = Contacts.add_note(scope, contact, %{body: "To delete"})
      assert {:ok, _} = Contacts.delete_note(scope, note)
    end

    test "returns unauthorized for viewer" do
      owner_scope = build_scope(:owner)
      {:ok, note} = Contacts.add_note(owner_scope, contact_fixture(owner_scope), %{body: "X"})

      viewer = insert(:user)
      membership = insert(:membership, user: viewer, organization: owner_scope.org, role: :viewer)
      viewer_scope = Scope.for_user_in_org(viewer, owner_scope.org, membership)

      assert {:error, :unauthorized} = Contacts.delete_note(viewer_scope, note)
    end
  end

  # ---------------------------------------------------------------------------
  # Note.changeset/2
  # ---------------------------------------------------------------------------

  describe "Note.changeset/2" do
    test "requires body" do
      changeset = Note.changeset(%Note{}, %{})
      assert "can't be blank" in errors_on(changeset).body
    end

    test "accepts is_internal flag" do
      changeset = Note.changeset(%Note{}, %{body: "Internal note", is_internal: true})
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :is_internal) == true
    end
  end
end
