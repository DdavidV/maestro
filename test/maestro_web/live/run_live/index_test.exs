defmodule MaestroWeb.RunLive.IndexTest do
  use MaestroWeb.LiveViewCase, async: false

  import Maestro.WorkspaceFixtures

  alias Maestro.Core.Runner

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
  end

  defp suite(id) do
    %{
      "id" => id,
      "testcases" => [
        %{
          "id" => "tc1",
          "steps" => [
            %{
              "client" => "test_client_no_optional",
              "template" => %{
                "clients" => ["test_client_no_optional"],
                "payload" => %{"a" => 1}
              },
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

  test "lists every run for this workspace, newest first", %{conn: conn, workspace: workspace} do
    resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))

    {:ok, run_id_1} = Runner.run(workspace, ["checkout/smoke"])
    wait_until_done(run_id_1)
    {:ok, run_id_2} = Runner.run(workspace, ["checkout/smoke"])
    wait_until_done(run_id_2)

    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/history")

    rows = view |> element("tbody") |> render() |> then(&Regex.scan(~r/run_\d+_\S+/, &1))
    run_ids = rows |> List.flatten() |> Enum.uniq()

    assert Enum.find_index(run_ids, &(&1 == run_id_2)) <
             Enum.find_index(run_ids, &(&1 == run_id_1))

    assert has_element?(view, ".badge-success", "ok")
  end

  test "shows an empty state with no runs", %{conn: conn, workspace: workspace} do
    {:ok, _view, html} = live(conn, ~p"/workspace/#{workspace.id}/history")

    assert html =~ "No runs yet"
  end

  test "removing one run leaves the others", %{conn: conn, workspace: workspace} do
    resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))

    {:ok, run_id_1} = Runner.run(workspace, ["checkout/smoke"])
    wait_until_done(run_id_1)
    {:ok, run_id_2} = Runner.run(workspace, ["checkout/smoke"])
    wait_until_done(run_id_2)

    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/history")

    view
    |> element("button[phx-click=delete][phx-value-run_id='#{run_id_1}']")
    |> render_click()

    html = render(view)
    refute html =~ run_id_1
    assert html =~ run_id_2
    assert Runner.result(run_id_1) == {:error, :not_found}
  end

  test "clearing history removes every run and shows the empty state", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))

    {:ok, run_id} = Runner.run(workspace, ["checkout/smoke"])
    wait_until_done(run_id)

    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/history")

    view |> element("button", "Clear history") |> render_click()

    html = render(view)
    assert html =~ "No runs yet"
    assert Runner.result(run_id) == {:error, :not_found}
  end

  test "a run in another workspace doesn't show up here", %{conn: conn, workspace: workspace} do
    other_workspace = workspace_fixture()
    resource_fixture!(other_workspace, :suite, "checkout/smoke", suite("checkout-smoke"))

    {:ok, run_id} = Runner.run(other_workspace, ["checkout/smoke"])
    wait_until_done(run_id)

    {:ok, _view, html} = live(conn, ~p"/workspace/#{workspace.id}/history")

    assert html =~ "No runs yet"
    refute html =~ run_id
  end
end
