defmodule MaestroWeb.WorkspaceLive.Explorer.TestPlanTest do
  use MaestroWeb.LiveViewCase, async: false

  import Maestro.WorkspaceFixtures

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
  end

  defp test_plan(id, suites) do
    %{"id" => id, "test_suites" => suites}
  end

  describe "index" do
    test "lists every test plan in the workspace", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :test_plan, "nightly", test_plan("nightly", ["a/b"]))

      {:ok, _view, html} = live(conn, ~p"/workspace/#{workspace.id}/test_plans")

      assert html =~ "nightly"
    end

    test "search filters by path/name", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :test_plan, "nightly", test_plan("nightly", ["a/b"]))
      resource_fixture!(workspace, :test_plan, "weekly", test_plan("weekly", ["a/b"]))

      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/test_plans")

      view |> form("#search-form", %{"query" => "night"}) |> render_change()

      assert has_element?(view, "tbody#test_plans a", "nightly")
      refute has_element?(view, "tbody#test_plans a", "weekly")
    end
  end

  describe "show" do
    test "renders referenced suites as links", %{conn: conn, workspace: workspace} do
      resource_fixture!(
        workspace,
        :test_plan,
        "nightly",
        test_plan("nightly", ["checkout/smoke"])
      )

      {:ok, _view, html} = live(conn, ~p"/workspace/#{workspace.id}/test_plans/nightly")

      assert html =~ "checkout/smoke"
      assert html =~ ~s(href="/workspace/#{workspace.id}/suites/checkout/smoke")
    end

    test "shows an error state for an unknown test plan path", %{conn: conn, workspace: workspace} do
      {:ok, _view, html} = live(conn, ~p"/workspace/#{workspace.id}/test_plans/does_not_exist")

      assert html =~ "Could not load this test plan"
    end
  end
end
