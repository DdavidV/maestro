defmodule MaestroWeb.ReportControllerTest do
  use MaestroWeb.ConnCase, async: false

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

  test "downloads a standalone HTML report matching Maestro.render_report/1's output", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))

    {:ok, run_id} = Runner.run(workspace, ["checkout/smoke"])
    wait_until_done(run_id)

    {:ok, expected_html} = Maestro.render_report(run_id)

    conn = get(conn, ~p"/workspace/#{workspace.id}/reports/#{run_id}/download")

    assert conn.status == 200
    # `Maestro.render_report/1` stamps a fresh `generated_at` on every call
    # (`Model.build/1` calls `DateTime.utc_now()`), so this is the one line
    # expected to legitimately differ between the two independent calls
    # made a few microseconds apart; everything else must match exactly.
    assert strip_generated_at(conn.resp_body) == strip_generated_at(expected_html)
    assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="maestro_report_#{run_id}.html")
           ]
  end

  defp strip_generated_at(html), do: Regex.replace(~r/Generated .*?<\/p>/, html, "Generated</p>")

  test "the downloaded report is standalone (has its own <style>, no external asset refs)", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))

    {:ok, run_id} = Runner.run(workspace, ["checkout/smoke"])
    wait_until_done(run_id)

    conn = get(conn, ~p"/workspace/#{workspace.id}/reports/#{run_id}/download")

    assert conn.resp_body =~ "<style>"
    refute conn.resp_body =~ "<link rel=\"stylesheet\""
    refute conn.resp_body =~ "<script src="
  end

  test "an unknown run_id redirects with a flash instead of downloading", %{
    conn: conn,
    workspace: workspace
  } do
    conn = get(conn, ~p"/workspace/#{workspace.id}/reports/does_not_exist/download")

    assert redirected_to(conn) == "/workspace/#{workspace.id}"
  end

  test "a run belonging to a different workspace is rejected", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))
    {:ok, run_id} = Runner.run(workspace, ["checkout/smoke"])
    wait_until_done(run_id)

    other_workspace = workspace_fixture()

    conn = get(conn, ~p"/workspace/#{other_workspace.id}/reports/#{run_id}/download")

    assert redirected_to(conn) == "/workspace/#{other_workspace.id}"
  end
end
