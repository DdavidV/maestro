defmodule MaestroWeb.BreadcrumbsTest do
  use MaestroWeb.LiveViewCase, async: false

  import Maestro.WorkspaceFixtures

  alias Maestro.Core.Runner

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
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

  defp suite(id) do
    %{
      "id" => id,
      "testcases" => [
        %{
          "id" => "tc1",
          "steps" => [
            %{
              "client" => "http",
              "template" => %{"clients" => ["http"], "payload" => %{"a" => 1}},
              "dataset" => %{"data" => %{"a" => 1}}
            }
          ]
        }
      ]
    }
  end

  test "index shows just the kind, unlinked", %{conn: conn, workspace: workspace} do
    {:ok, view, html} = live(conn, ~p"/workspace/#{workspace.id}/suites")

    assert html =~ "Suites"
    refute has_element?(view, "a[href='/workspace/#{workspace.id}/suites']", "Suites")
  end

  test "show links back to the index, then the current path unlinked", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))

    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/suites/checkout/smoke")

    assert has_element?(view, "a[href='/workspace/#{workspace.id}/suites']", "Suites")
    assert html_contains_unlinked_crumb?(render(view), "checkout/smoke")
  end

  test "new links back to the index, then 'New' unlinked", %{conn: conn, workspace: workspace} do
    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/suites/new")

    assert has_element?(view, "a[href='/workspace/#{workspace.id}/suites']", "Suites")
    assert html_contains_unlinked_crumb?(render(view), "New")
  end

  test "edit links back to the index and the show page, then 'Edit' unlinked", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))

    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/suites/edit/checkout/smoke")

    assert has_element?(view, "a[href='/workspace/#{workspace.id}/suites']", "Suites")

    assert has_element?(
             view,
             "a[href='/workspace/#{workspace.id}/suites/checkout/smoke']",
             "checkout/smoke"
           )

    assert html_contains_unlinked_crumb?(render(view), "Edit")
  end

  test "dashboard shows just the workspace name, unlinked", %{conn: conn, workspace: workspace} do
    {:ok, view, html} = live(conn, ~p"/workspace/#{workspace.id}")

    assert html =~ workspace.name
    assert html_contains_unlinked_crumb?(render(view), workspace.name)
  end

  test "every non-dashboard page's breadcrumb links the workspace name back to the dashboard", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))

    for path <- [
          "/workspace/#{workspace.id}/suites",
          "/workspace/#{workspace.id}/suites/checkout/smoke",
          "/workspace/#{workspace.id}/suites/new",
          "/workspace/#{workspace.id}/run",
          "/workspace/#{workspace.id}/history"
        ] do
      {:ok, view, _html} = live(conn, path)

      assert has_element?(
               view,
               "a[href='/workspace/#{workspace.id}']",
               workspace.name
             ),
             "expected #{path} to link the workspace name back to /workspace/#{workspace.id}"
    end
  end

  test "the run picker shows 'Run', unlinked", %{conn: conn, workspace: workspace} do
    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/run")

    assert html_contains_unlinked_crumb?(render(view), "Run")
  end

  test "the history list shows 'History', unlinked", %{conn: conn, workspace: workspace} do
    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/history")

    assert html_contains_unlinked_crumb?(render(view), "History")
  end

  test "a run's show page links back to History, then the run_id unlinked", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))
    {:ok, run_id} = Runner.run(workspace, ["checkout/smoke"])
    wait_until_done(run_id)

    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/history/#{run_id}")

    assert has_element?(view, "a[href='/workspace/#{workspace.id}/history']", "History")
    assert html_contains_unlinked_crumb?(render(view), run_id)
  end

  test "the report page links back to History and the run's show page, then 'Report' unlinked", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))
    {:ok, run_id} = Runner.run(workspace, ["checkout/smoke"])
    wait_until_done(run_id)

    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/reports/#{run_id}")

    assert has_element?(view, "a[href='/workspace/#{workspace.id}/history']", "History")

    assert has_element?(
             view,
             "a[href='/workspace/#{workspace.id}/history/#{run_id}']",
             run_id
           )

    assert html_contains_unlinked_crumb?(render(view), "Report")
  end

  defp html_contains_unlinked_crumb?(html, label) do
    html =~ ~r/<span[^>]*>#{Regex.escape(label)}<\/span>/
  end
end
