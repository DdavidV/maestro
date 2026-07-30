defmodule MaestroWeb.RunLive.ShowTest do
  use MaestroWeb.LiveViewCase, async: false

  import Maestro.WorkspaceFixtures

  alias Maestro.Core.Runner

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
  end

  defp suite(id, opts \\ []) do
    client = Keyword.get(opts, :client, "test_client_no_optional")

    %{
      "id" => id,
      "testcases" => [
        %{
          "id" => "tc1",
          "steps" => [
            %{
              "client" => client,
              "template" => %{"clients" => [client], "payload" => %{"a" => 1}},
              "dataset" => %{"data" => %{"a" => 1}}
            }
          ]
        }
      ]
    }
  end

  defp wait_until_done(run_id, tries \\ 50) do
    {:ok, progress} = Runner.status(run_id)

    if progress.status in [:ok, :error] or tries == 0 do
      progress
    else
      Process.sleep(20)
      wait_until_done(run_id, tries - 1)
    end
  end

  describe "triggering a run from the suite show page" do
    test "clicking Run navigates to the run's show page", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))

      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/suites/checkout/smoke")

      assert {:error, {:live_redirect, %{to: to}}} =
               view |> element("button", "Run") |> render_click()

      assert to =~ ~r{^/workspace/#{workspace.id}/history/run_}
    end

    test "clicking Run on a test plan navigates to the run's show page", %{
      conn: conn,
      workspace: workspace
    } do
      resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))

      resource_fixture!(workspace, :test_plan, "nightly", %{
        "id" => "nightly",
        "test_suites" => ["checkout/smoke"]
      })

      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/test_plans/nightly")

      assert {:error, {:live_redirect, %{to: to}}} =
               view |> element("button", "Run") |> render_click()

      assert to =~ ~r{^/workspace/#{workspace.id}/history/run_}
    end
  end

  describe "show" do
    test "renders live progress as testcases/suites finish", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))

      {:ok, workspace_struct} = Maestro.Workspaces.get(workspace.id)
      {:ok, run_id} = Runner.run(workspace_struct, ["checkout/smoke"])

      wait_until_done(run_id)

      {:ok, view, html} = live(conn, ~p"/workspace/#{workspace.id}/history/#{run_id}")

      assert html =~ run_id
      assert has_element?(view, "span", "checkout-smoke")
      assert has_element?(view, "span", "tc1")
      assert has_element?(view, ".badge-success", "ok")
    end

    test "updates live as broadcasts arrive, without a manual refresh", %{
      conn: conn,
      workspace: workspace
    } do
      resource_fixture!(
        workspace,
        :suite,
        "checkout/smoke",
        suite("checkout-smoke", client: "test_client_slow")
      )

      {:ok, workspace_struct} = Maestro.Workspaces.get(workspace.id)
      {:ok, run_id} = Runner.run(workspace_struct, ["checkout/smoke"])

      {:ok, view, html} = live(conn, ~p"/workspace/#{workspace.id}/history/#{run_id}")

      assert html =~ "running"
      refute html =~ "badge-success"

      wait_until_done(run_id)
      assert render(view) =~ "badge-success"
    end

    test "a run belonging to a different workspace is rejected", %{
      conn: conn,
      workspace: workspace
    } do
      resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))
      {:ok, run_id} = Runner.run(workspace, ["checkout/smoke"])
      wait_until_done(run_id)

      other_workspace = workspace_fixture()

      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, ~p"/workspace/#{other_workspace.id}/history/#{run_id}")

      assert to == "/workspace/#{other_workspace.id}"
    end

    test "an unknown run_id redirects with a flash", %{conn: conn, workspace: workspace} do
      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, ~p"/workspace/#{workspace.id}/history/does_not_exist")

      assert to == "/workspace/#{workspace.id}"
    end
  end
end
