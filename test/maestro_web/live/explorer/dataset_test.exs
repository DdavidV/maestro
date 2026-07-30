defmodule MaestroWeb.WorkspaceLive.Explorer.DatasetTest do
  use MaestroWeb.LiveViewCase, async: false

  import Maestro.WorkspaceFixtures

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
  end

  describe "index" do
    test "lists every dataset in the workspace", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :dataset, "test_user", %{"data" => %{"username" => "alice"}})

      {:ok, _view, html} = live(conn, ~p"/workspace/#{workspace.id}/datasets")

      assert html =~ "test_user"
    end

    test "search filters by path/name", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :dataset, "test_user", %{"data" => %{"a" => 1}})
      resource_fixture!(workspace, :dataset, "seeded_users", %{"rows" => [%{"a" => 1}]})

      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/datasets")

      view |> form("#search-form", %{"query" => "seeded"}) |> render_change()

      assert has_element?(view, "tbody#datasets a", "seeded_users")
      refute has_element?(view, "tbody#datasets a", "test_user")
    end
  end

  describe "show" do
    test "renders a 'data' body read-only", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :dataset, "test_user", %{
        "data" => %{"username" => "alice", "password" => "secret"}
      })

      {:ok, _view, html} = live(conn, ~p"/workspace/#{workspace.id}/datasets/test_user")

      assert html =~ "alice"
      assert html =~ "secret"
    end

    test "renders a 'rows' body read-only", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :dataset, "seeded_users", %{
        "rows" => [%{"username" => "alice"}, %{"username" => "bob"}]
      })

      {:ok, _view, html} = live(conn, ~p"/workspace/#{workspace.id}/datasets/seeded_users")

      assert html =~ "alice"
      assert html =~ "bob"
    end

    test "shows an error state for an unknown dataset path", %{conn: conn, workspace: workspace} do
      {:ok, _view, html} = live(conn, ~p"/workspace/#{workspace.id}/datasets/does_not_exist")

      assert html =~ "Could not load this dataset"
    end

    test "deleting removes the file and navigates back to the index", %{
      conn: conn,
      workspace: workspace
    } do
      resource_fixture!(workspace, :dataset, "test_user", %{"data" => %{"username" => "alice"}})

      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/datasets/test_user")

      {:ok, index_live, html} =
        view
        |> element("button", "Delete")
        |> render_click()
        |> follow_redirect(conn)

      assert html =~ "Deleted test_user."
      refute has_element?(index_live, "tbody#datasets a", "test_user")
      assert Maestro.Resources.fetch(workspace, :dataset, "test_user") == {:error, :not_found}
    end
  end
end
