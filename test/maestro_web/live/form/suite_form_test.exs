defmodule MaestroWeb.WorkspaceLive.Form.SuiteFormTest do
  use MaestroWeb.LiveViewCase, async: false

  import Maestro.WorkspaceFixtures

  alias Maestro.Resources

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
  end

  describe "new" do
    test "creating a suite with one testcase and one template-step with a dataset", %{
      conn: conn,
      workspace: workspace
    } do
      resource_fixture!(workspace, :template, "login_request", %{
        "clients" => ["http"],
        "payload" => %{"username" => "{{username}}"}
      })

      resource_fixture!(workspace, :dataset, "test_user", %{"data" => %{"username" => "alice"}})

      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/suites/new")

      view |> element("#resource-path") |> render_change(%{"path" => "checkout/smoke"})

      view
      |> element("input[name=resource_id]")
      |> render_change(%{"resource_id" => "checkout-smoke"})

      view |> element("button", "Add testcase") |> render_click()

      view
      |> element("input[name='testcases[0][id]']")
      |> render_change(%{"testcases" => %{"0" => %{"id" => "login-tc"}}})

      view
      |> element(~s{button[phx-click="step-add-template"][phx-value-testcase_index="0"]})
      |> render_click()

      view
      |> element("select[name='steps[0][0][client]']")
      |> render_change(%{"steps" => %{"0" => %{"0" => %{"client" => "http"}}}})

      view |> element(~s{[id="template-picker-0-0"] button}, "Change") |> render_click()

      view
      |> element(
        ~s{[id="template-picker-0-0"] a[phx-value-entry_path="login_request"]},
        "login_request"
      )
      |> render_click()

      view |> element(~s{[id="dataset-picker-0-0"] button}, "Change") |> render_click()

      view
      |> element(~s{[id="dataset-picker-0-0"] a[phx-value-entry_path="test_user"]}, "test_user")
      |> render_click()

      {:error, {:live_redirect, %{to: to}}} = view |> element("form") |> render_submit()

      assert to == "/workspace/#{workspace.id}/suites/checkout/smoke"

      assert {:ok,
              %{
                "id" => "checkout-smoke",
                "testcases" => [
                  %{
                    "id" => "login-tc",
                    "steps" => [
                      %{
                        "client" => "http",
                        "template" => "login_request",
                        "dataset" => "test_user"
                      }
                    ]
                  }
                ]
              }} = Resources.fetch(workspace, :suite, "checkout/smoke")
    end

    test "removing a testcase", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/suites/new")

      view |> element("button", "Add testcase") |> render_click()
      view |> element("button", "Add testcase") |> render_click()
      assert view |> render() =~ "testcase #2"

      view
      |> element(~s{button[phx-value-index="0"]}, "Remove testcase")
      |> render_click()

      html = view |> render()
      refute html =~ "testcase #2"
      assert html =~ "testcase #1"
    end

    test "shows a validation error when a testcase has no steps", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/suites/new")

      view |> element("#resource-path") |> render_change(%{"path" => "empty_suite"})

      view
      |> element("input[name=resource_id]")
      |> render_change(%{"resource_id" => "empty-suite"})

      view |> element("button", "Add testcase") |> render_click()

      view
      |> element("input[name='testcases[0][id]']")
      |> render_change(%{"testcases" => %{"0" => %{"id" => "tc"}}})

      html = view |> element("form") |> render_submit()

      assert html =~ "minimum of 1 items"
      assert Resources.fetch(workspace, :suite, "empty_suite") == {:error, :not_found}
    end
  end
end
