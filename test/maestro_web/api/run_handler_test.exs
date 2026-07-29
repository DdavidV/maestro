defmodule MaestroWeb.API.RunHandlerTest do
  use MaestroWeb.ConnCase, async: false

  import Maestro.WorkspaceFixtures

  @valid_suite %{
    "id" => "api_smoke_suite",
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

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
  end

  defp wait_until_done(run_id, tries \\ 50) do
    {:ok, progress} = Maestro.status(run_id)

    if progress.status in [:ok, :error] or tries == 0 do
      progress
    else
      Process.sleep(20)
      wait_until_done(run_id, tries - 1)
    end
  end

  describe "POST /api/run" do
    defp post_run(conn, body) when is_map(body) do
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/run", Jason.encode!(body))
    end

    defp post_run(conn, non_map_body) do
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/run", Jason.encode!(non_map_body))
    end

    test "202s and starts a run for a valid inline suite", %{conn: conn, workspace: workspace} do
      conn = post_run(conn, %{"workspace_id" => workspace.id, "entries" => [@valid_suite]})

      assert %{"run_id" => run_id} = json_response(conn, 202)
      assert is_binary(run_id)

      final = wait_until_done(run_id)
      assert final.status == :ok
    end

    test "accepts a mix of inline suites and file-path references", %{
      conn: conn,
      workspace: workspace
    } do
      resource_fixture!(workspace, :suite, "api_ref_suite", @valid_suite)

      conn =
        post_run(conn, %{
          "workspace_id" => workspace.id,
          "entries" => ["api_ref_suite", @valid_suite]
        })

      assert %{"run_id" => run_id} = json_response(conn, 202)
      final = wait_until_done(run_id)
      assert final.status == :ok
    end

    test "422s with per-index errors when a suite fails to resolve", %{
      conn: conn,
      workspace: workspace
    } do
      conn =
        post_run(conn, %{
          "workspace_id" => workspace.id,
          "entries" => ["does/not/exist", @valid_suite]
        })

      assert %{"errors" => [%{"index" => 0, "reason" => "not_found"}]} =
               json_response(conn, 422)
    end

    test "404s for an unknown workspace_id", %{conn: conn} do
      conn =
        post_run(conn, %{"workspace_id" => "does-not-exist", "entries" => [@valid_suite]})

      assert %{"error" => %{"workspace_not_found" => "does-not-exist"}} =
               json_response(conn, 404)
    end

    test "400s when workspace_id is missing", %{conn: conn} do
      conn = post_run(conn, %{"entries" => [@valid_suite]})

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "workspace_id"
    end

    test "400s when entries is missing", %{conn: conn, workspace: workspace} do
      conn = post_run(conn, %{"workspace_id" => workspace.id})

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "entries"
    end

    test "400s when entries isn't an array", %{conn: conn, workspace: workspace} do
      conn = post_run(conn, %{"workspace_id" => workspace.id, "entries" => "not-a-list"})

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "entries"
    end

    test "400s when the body is not an object at all", %{conn: conn} do
      conn = post_run(conn, "not-an-object")

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "workspace_id"
    end
  end

  describe "POST /api/workspaces/:workspace_id/test-plan/:name/run" do
    test "202s and runs every suite in the named test plan", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :suite, "api_plan_suite", @valid_suite)

      resource_fixture!(workspace, :test_plan, "api_nightly", %{
        "id" => "api_nightly",
        "test_suites" => ["api_plan_suite"]
      })

      conn = post(conn, ~p"/api/workspaces/#{workspace.id}/test-plan/api_nightly/run")

      assert %{"run_id" => run_id} = json_response(conn, 202)
      final = wait_until_done(run_id)
      assert final.status == :ok
    end

    test "404s for an unknown test plan name", %{conn: conn, workspace: workspace} do
      conn = post(conn, ~p"/api/workspaces/#{workspace.id}/test-plan/does-not-exist/run")

      assert %{"error" => %{"test_plan_not_found" => "does-not-exist"}} =
               json_response(conn, 404)
    end

    test "404s for an unknown workspace_id", %{conn: conn} do
      conn = post(conn, ~p"/api/workspaces/does-not-exist/test-plan/anything/run")

      assert %{"error" => %{"workspace_not_found" => "does-not-exist"}} =
               json_response(conn, 404)
    end
  end

  describe "GET /api/runs/:run_id/status" do
    test "200s with per-suite progress", %{conn: conn, workspace: workspace} do
      {:ok, run_id} = Maestro.run(workspace, [@valid_suite])
      wait_until_done(run_id)

      conn = get(conn, ~p"/api/runs/#{run_id}/status")

      assert %{"run_id" => ^run_id, "status" => "ok", "suites" => [%{"id" => "api_smoke_suite"}]} =
               json_response(conn, 200)
    end

    test "404s for an unknown run_id", %{conn: conn} do
      conn = get(conn, ~p"/api/runs/does-not-exist/status")
      assert json_response(conn, 404)
    end
  end

  describe "GET /api/runs/:run_id" do
    test "200s with the full result", %{conn: conn, workspace: workspace} do
      {:ok, run_id} = Maestro.run(workspace, [@valid_suite])
      wait_until_done(run_id)

      conn = get(conn, ~p"/api/runs/#{run_id}")

      assert %{"run_id" => ^run_id, "suites" => [%{"id" => "api_smoke_suite"}]} =
               json_response(conn, 200)
    end

    test "scopes to one suite with ?suite_id=", %{conn: conn, workspace: workspace} do
      {:ok, run_id} = Maestro.run(workspace, [@valid_suite])
      wait_until_done(run_id)

      conn = get(conn, ~p"/api/runs/#{run_id}?suite_id=api_smoke_suite")

      assert %{"id" => "api_smoke_suite", "testcases" => [%{"id" => "tc1"}]} =
               json_response(conn, 200)
    end

    test "scopes to one testcase with ?suite_id=&testcase_id=", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, run_id} = Maestro.run(workspace, [@valid_suite])
      wait_until_done(run_id)

      conn = get(conn, ~p"/api/runs/#{run_id}?suite_id=api_smoke_suite&testcase_id=tc1")

      assert %{"id" => "tc1", "steps" => [_step]} = json_response(conn, 200)
    end

    test "encodes assertion failures (AssertionResult/Reason) without crashing", %{
      conn: conn,
      workspace: workspace
    } do
      suite = %{
        "id" => "api_assert_suite",
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
                "dataset" => %{"data" => %{"a" => 1}},
                "assert" => [%{"expected" => %{"nonexistent_field" => "will_fail"}}]
              }
            ]
          }
        ]
      }

      {:ok, run_id} = Maestro.run(workspace, [suite])
      wait_until_done(run_id)

      conn = get(conn, ~p"/api/runs/#{run_id}")

      assert %{"suites" => [%{"testcases" => [%{"steps" => [step]}]}]} =
               json_response(conn, 200)

      assert %{"assertions" => [%{"status" => "error", "reasons" => [reason]}]} = step
      assert reason["reason"] == "expected_key_missing"
    end

    test "encodes a dispatch failure (Client.Error) without crashing", %{
      conn: conn,
      workspace: workspace
    } do
      suite = %{
        "id" => "api_error_suite",
        "testcases" => [
          %{
            "id" => "tc1",
            "steps" => [
              %{
                "client" => "does_not_exist",
                "template" => %{"clients" => ["does_not_exist"], "payload" => %{}},
                "dataset" => %{"data" => %{"a" => 1}}
              }
            ]
          }
        ]
      }

      {:ok, run_id} = Maestro.run(workspace, [suite])
      wait_until_done(run_id)

      conn = get(conn, ~p"/api/runs/#{run_id}")

      assert %{"suites" => [%{"testcases" => [%{"steps" => [step]}]}]} =
               json_response(conn, 200)

      assert %{"response" => %{"stage" => "client_lookup", "reason" => "client_not_found"}} = step
    end

    test "404s for an unknown run_id", %{conn: conn} do
      conn = get(conn, ~p"/api/runs/does-not-exist")
      assert json_response(conn, 404)
    end
  end

  describe "GET /api/runs/:run_id/report" do
    test "200s with the rendered HTML report", %{conn: conn, workspace: workspace} do
      {:ok, run_id} = Maestro.run(workspace, [@valid_suite])
      wait_until_done(run_id)

      conn = get(conn, ~p"/api/runs/#{run_id}/report")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> List.first() =~ "text/html"
      assert conn.resp_body =~ "<html"
    end

    test "404s for an unknown run_id", %{conn: conn} do
      conn = get(conn, ~p"/api/runs/does-not-exist/report")
      assert json_response(conn, 404)
    end
  end

  describe "POST /api/runs/:run_id/report" do
    test "201s and writes the report to disk", %{conn: conn, workspace: workspace} do
      {:ok, run_id} = Maestro.run(workspace, [@valid_suite])
      wait_until_done(run_id)

      conn = post(conn, ~p"/api/runs/#{run_id}/report")

      assert %{"run_id" => ^run_id, "path" => path} = json_response(conn, 201)
      assert File.exists?(path)
    end

    test "404s for an unknown run_id", %{conn: conn} do
      conn = post(conn, ~p"/api/runs/does-not-exist/report")
      assert json_response(conn, 404)
    end
  end
end
