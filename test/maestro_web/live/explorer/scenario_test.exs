defmodule MaestroWeb.WorkspaceLive.Explorer.ScenarioTest do
  use MaestroWeb.LiveViewCase, async: false

  import Maestro.WorkspaceFixtures

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
  end

  defp scenario(name) do
    %{
      "name" => name,
      "default_dataset" => %{"data" => %{"password" => "default"}},
      "steps" => [
        %{
          "name" => "POST /login",
          "client" => "http",
          "template" => %{"clients" => ["http"], "payload" => %{"a" => 1}}
        }
      ]
    }
  end

  describe "index" do
    test "lists every scenario in the workspace", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :scenario, "login_and_get_token", scenario("login"))

      {:ok, _view, html} = live(conn, ~p"/workspace/#{workspace.id}/scenarios")

      assert html =~ "login_and_get_token"
    end

    test "search filters by path/name", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :scenario, "login_and_get_token", scenario("login"))
      resource_fixture!(workspace, :scenario, "logout", scenario("logout"))

      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/scenarios")

      view |> form("#search-form", %{"query" => "login_and"}) |> render_change()

      assert has_element?(view, "tbody#scenarios a", "login_and_get_token")
      refute has_element?(view, "tbody#scenarios a", "logout")
    end
  end

  describe "show" do
    test "renders steps and default_dataset read-only", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :scenario, "login_and_get_token", scenario("login"))

      {:ok, _view, html} =
        live(conn, ~p"/workspace/#{workspace.id}/scenarios/login_and_get_token")

      assert html =~ "POST /login"
      assert html =~ "default"
    end

    test "shows an error state for an unknown scenario path", %{conn: conn, workspace: workspace} do
      {:ok, _view, html} = live(conn, ~p"/workspace/#{workspace.id}/scenarios/does_not_exist")

      assert html =~ "Could not load this scenario"
    end
  end
end
