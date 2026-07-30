defmodule MaestroWeb.ReportLive.ShowTest do
  use MaestroWeb.LiveViewCase, async: false

  import Maestro.WorkspaceFixtures

  alias Maestro.Core.Runner

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
  end

  defp suite_with_assert(id, expected) do
    %{
      "id" => id,
      "testcases" => [
        %{
          "id" => "tc1",
          "steps" => [
            %{
              "name" => "call it",
              "client" => "test_client_no_optional",
              "template" => %{
                "clients" => ["test_client_no_optional"],
                "payload" => %{"a" => 1}
              },
              "dataset" => %{"data" => %{"a" => 1}},
              "assert" => [
                %{"matcher" => "json_match", "path" => "$.echo.payload.a", "expected" => expected}
              ]
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

  test "renders every suite/testcase/step/assertion from the model", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :suite, "checkout/smoke", suite_with_assert("checkout-smoke", 1))

    {:ok, run_id} = Runner.run(workspace, ["checkout/smoke"])
    wait_until_done(run_id)

    {:ok, view, html} = live(conn, ~p"/workspace/#{workspace.id}/reports/#{run_id}")

    assert html =~ run_id
    assert has_element?(view, "span", "checkout-smoke")
    assert has_element?(view, "span", "tc1")
    assert has_element?(view, "span", "call it")
    assert has_element?(view, "span", "json_match")
    assert has_element?(view, ".badge-success", "ok")
  end

  test "shows a failure's matcher/path/expected/actual detail", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(
      workspace,
      :suite,
      "checkout/smoke",
      suite_with_assert("checkout-smoke", 999)
    )

    {:ok, run_id} = Runner.run(workspace, ["checkout/smoke"])
    wait_until_done(run_id)

    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/reports/#{run_id}")

    html = render(view)
    assert html =~ "path: $.echo.payload.a"
    assert html =~ "expected: 999"
    assert has_element?(view, ".badge-error", "error")
  end

  test "has a link back to the run page and a download link", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :suite, "checkout/smoke", suite_with_assert("checkout-smoke", 1))

    {:ok, run_id} = Runner.run(workspace, ["checkout/smoke"])
    wait_until_done(run_id)

    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/reports/#{run_id}")

    assert has_element?(view, "a[href='/workspace/#{workspace.id}/history/#{run_id}']")
    assert has_element?(view, "a[href='/workspace/#{workspace.id}/reports/#{run_id}/download']")
  end

  test "updates live as broadcasts arrive", %{conn: conn, workspace: workspace} do
    suite =
      put_in(
        suite_with_assert("checkout-smoke", 1),
        ["testcases", Access.at(0), "steps", Access.at(0), "client"],
        "test_client_slow"
      )

    suite =
      put_in(
        suite,
        ["testcases", Access.at(0), "steps", Access.at(0), "template", "clients"],
        ["test_client_slow"]
      )

    resource_fixture!(workspace, :suite, "checkout/smoke", suite)

    {:ok, run_id} = Runner.run(workspace, ["checkout/smoke"])

    {:ok, view, html} = live(conn, ~p"/workspace/#{workspace.id}/reports/#{run_id}")

    assert html =~ "running"
    refute html =~ "badge-success"

    wait_until_done(run_id)
    assert render(view) =~ "badge-success"
  end

  test "a run belonging to a different workspace is rejected", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :suite, "checkout/smoke", suite_with_assert("checkout-smoke", 1))
    {:ok, run_id} = Runner.run(workspace, ["checkout/smoke"])
    wait_until_done(run_id)

    other_workspace = workspace_fixture()

    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, ~p"/workspace/#{other_workspace.id}/reports/#{run_id}")

    assert to == "/workspace/#{other_workspace.id}"
  end

  test "an unknown run_id redirects with a flash", %{conn: conn, workspace: workspace} do
    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, ~p"/workspace/#{workspace.id}/reports/does_not_exist")

    assert to == "/workspace/#{workspace.id}"
  end
end
