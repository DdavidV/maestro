defmodule MaestroWeb.WorkspaceLive.Form.TestPlanFormTest do
  use MaestroWeb.LiveViewCase, async: false

  import Maestro.WorkspaceFixtures

  alias Maestro.Resources

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
  end

  describe "new" do
    test "creating a test plan referencing an existing suite", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :suite, "checkout/smoke", %{
        "id" => "smoke",
        "testcases" => [%{"id" => "tc", "steps" => [%{"scenario" => "x", "dataset" => "x"}]}]
      })

      {:ok, view, html} = live(conn, ~p"/workspace/#{workspace.id}/test_plans/new")

      assert html =~ "checkout/smoke"

      view |> element("#resource-path") |> render_change(%{"path" => "nightly"})

      view
      |> element("input[type=checkbox][phx-value-path=\"checkout/smoke\"]")
      |> render_click()

      view
      |> element("input[name=resource_id]")
      |> render_change(%{"resource_id" => "nightly-regression"})

      {:error, {:live_redirect, %{to: to}}} = view |> element("form") |> render_submit()

      assert to == "/workspace/#{workspace.id}/test_plans/nightly"

      assert {:ok, %{"id" => "nightly-regression", "test_suites" => ["checkout/smoke"]}} =
               Resources.fetch(workspace, :test_plan, "nightly")
    end

    test "shows a validation error when saving without an id", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :suite, "checkout/smoke", %{
        "id" => "smoke",
        "testcases" => [%{"id" => "tc", "steps" => [%{"scenario" => "x", "dataset" => "x"}]}]
      })

      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/test_plans/new")

      view |> element("#resource-path") |> render_change(%{"path" => "nightly"})

      view
      |> element("input[type=checkbox][phx-value-path=\"checkout/smoke\"]")
      |> render_click()

      html = view |> element("form") |> render_submit()

      assert html =~ "minimum length"
      assert Resources.fetch(workspace, :test_plan, "nightly") == {:error, :not_found}
    end
  end
end
