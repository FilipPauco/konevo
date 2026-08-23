defmodule Konevo.CompaniesTest do
  use Konevo.DataCase, async: true

  import Konevo.Factory
  import Konevo.CompaniesFixtures
  import Konevo.ContactsFixtures

  alias Konevo.Accounts.Scope
  alias Konevo.Companies
  alias Konevo.Companies.Company

  setup do
    %{scope: build_scope()}
  end

  describe "list_companies/2" do
    test "scopes, searches and filters companies", %{scope: scope} do
      acme =
        company_fixture(scope, %{
          name: "Acme Labs",
          industry: "Software",
          website: "https://acme.test"
        })

      _other = company_fixture(scope, %{name: "Northwind", industry: "Retail"})
      hidden = company_fixture(build_scope(), %{name: "Hidden Acme", industry: "Software"})

      {companies, total} =
        Companies.list_companies(scope, search: "acme", industries: ["Software"])

      assert Enum.map(companies, & &1.id) == [acme.id]
      refute hidden.id in Enum.map(companies, & &1.id)
      assert total == 1
    end

    test "returns contact counts", %{scope: scope} do
      company = company_fixture(scope)
      contact_fixture(scope, %{company: company})
      contact_fixture(scope, %{company: company})

      {[result], 1} = Companies.list_companies(scope, [])
      assert result.contact_count == 2
    end

    test "paginates and sorts", %{scope: scope} do
      Enum.each(["Charlie", "Alpha", "Bravo"], &company_fixture(scope, %{name: &1}))
      {first, 3} = Companies.list_companies(scope, page: 1, per_page: 2, sort_by: :name)
      {second, 3} = Companies.list_companies(scope, page: 2, per_page: 2, sort_by: :name)

      assert Enum.map(first, & &1.name) == ["Alpha", "Bravo"]
      assert Enum.map(second, & &1.name) == ["Charlie"]
    end
  end

  describe "company lifecycle" do
    test "creates, updates, fetches with contacts, and deletes", %{scope: scope} do
      assert {:ok, company} =
               Companies.create_company(scope, %{
                 name: "Acme",
                 website: "https://acme.test",
                 linkedin_url: "https://www.linkedin.com/company/acme"
               })

      assert company.organization_id == scope.org.id
      assert company.slug == "acme"
      assert company.linkedin_url == "https://www.linkedin.com/company/acme"
      assert {:ok, company} = Companies.update_company(scope, company, %{industry: "Software"})
      contact_fixture(scope, %{company: company})
      assert length(Companies.get_company!(scope, company.id).contacts) == 1
      assert {:ok, _company} = Companies.delete_company(scope, company)
      assert_raise Ecto.NoResultsError, fn -> Companies.get_company!(scope, company.id) end
    end

    test "rejects invalid data", %{scope: scope} do
      assert {:error, %Ecto.Changeset{}} =
               Companies.create_company(scope, %{name: "", website: "example.com"})
    end

    test "does not fetch another organization's company", %{scope: scope} do
      company = company_fixture(build_scope())
      assert_raise Ecto.NoResultsError, fn -> Companies.get_company!(scope, company.id) end
      assert {:error, :unauthorized} = Companies.update_company(scope, company, %{name: "Nope"})
    end

    test "viewer cannot mutate companies", %{scope: owner_scope} do
      company = company_fixture(owner_scope)
      viewer_scope = build_scope_for_org(owner_scope.org, :viewer)
      assert {:error, :unauthorized} = Companies.create_company(viewer_scope, %{name: "Nope"})

      assert {:error, :unauthorized} =
               Companies.update_company(viewer_scope, company, %{name: "Nope"})

      assert {:error, :unauthorized} = Companies.delete_company(viewer_scope, company)
    end

    test "generates duplicate slugs with hyphen suffixes", %{scope: scope} do
      assert {:ok, first} = Companies.create_company(scope, %{name: "Acme"})
      assert {:ok, second} = Companies.create_company(scope, %{name: "Acme"})

      assert first.slug == "acme"
      assert second.slug == "acme-1"
      assert Companies.get_company_by_slug_or_id!(scope, second.slug).id == second.id
    end

    test "refreshes slug when name changes", %{scope: scope} do
      company = company_fixture(scope)

      assert {:ok, updated} = Companies.update_company(scope, company, %{name: "New Name"})
      assert updated.slug == "new-name"
    end
  end

  describe "Company.changeset/2" do
    test "validates required name and website URL" do
      assert "can't be blank" in errors_on(Company.changeset(%Company{}, %{})).name

      assert "must start with http:// or https://" in errors_on(
               Company.changeset(%Company{}, %{name: "Acme", website: "acme.test"})
             ).website
    end

    test "validates LinkedIn URL format" do
      assert "must be a valid LinkedIn URL" in errors_on(
               Company.changeset(%Company{}, %{name: "Acme", linkedin_url: "example.com"})
             ).linkedin_url
    end
  end

  defp build_scope(role \\ :owner) do
    user = insert(:user)
    org = insert(:organization)
    membership = insert(:membership, user: user, organization: org, role: role)
    Scope.for_user_in_org(user, org, membership)
  end

  defp build_scope_for_org(org, role) do
    user = insert(:user)
    membership = insert(:membership, user: user, organization: org, role: role)
    Scope.for_user_in_org(user, org, membership)
  end
end
