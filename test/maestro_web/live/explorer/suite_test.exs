defmodule MaestroWeb.WorkspaceLive.Explorer.SuiteTest do
  use MaestroWeb.LiveViewCase, async: false

  import Maestro.WorkspaceFixtures

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
  end

  defp suite(id, opts \\ []) do
    %{
      "id" => id,
      "name" => Keyword.get(opts, :name, id),
      "tags" => Keyword.get(opts, :tags, []),
      "testcases" => [
        %{
          "id" => "tc1",
          "steps" => [
            %{
              "name" => "call it",
              "client" => "http",
              "template" => %{"clients" => ["http"], "payload" => %{"a" => 1}},
              "dataset" => %{"data" => %{"a" => 1}}
            }
          ]
        }
      ]
    }
  end

  describe "index" do
    test "lists every suite in the workspace", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))
      resource_fixture!(workspace, :suite, "accounts/login", suite("accounts-login"))

      {:ok, _view, html} = live(conn, ~p"/workspace/#{workspace.id}/suites")

      assert html =~ "checkout/smoke"
      assert html =~ "accounts/login"
    end

    test "search filters by path/name/tag", %{conn: conn, workspace: workspace} do
      resource_fixture!(
        workspace,
        :suite,
        "checkout/smoke",
        suite("checkout-smoke", tags: ["smoke"])
      )

      resource_fixture!(workspace, :suite, "accounts/login", suite("accounts-login"))

      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/suites")

      view |> form("form", %{"query" => "smoke"}) |> render_change()

      assert has_element?(view, "tbody#suites a", "checkout/smoke")
      refute has_element?(view, "tbody#suites a", "accounts/login")
    end
  end

  describe "show" do
    test "renders testcases and steps read-only", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))

      {:ok, _view, html} = live(conn, ~p"/workspace/#{workspace.id}/suites/checkout/smoke")

      assert html =~ "tc1"
      assert html =~ "call it"
      assert html =~ "http"
    end

    test "shows an error state for an unknown suite path", %{conn: conn, workspace: workspace} do
      {:ok, _view, html} = live(conn, ~p"/workspace/#{workspace.id}/suites/does/not/exist")

      assert html =~ "Could not load this suite"
    end

    test "deleting a nested path removes the file and navigates back to the index", %{
      conn: conn,
      workspace: workspace
    } do
      resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))

      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/suites/checkout/smoke")

      {:ok, index_live, html} =
        view
        |> element("button", "Delete")
        |> render_click()
        |> follow_redirect(conn)

      assert html =~ "Deleted checkout/smoke."
      refute has_element?(index_live, "tbody#suites a", "checkout/smoke")
      assert Maestro.Resources.fetch(workspace, :suite, "checkout/smoke") == {:error, :not_found}
    end
  end
end
