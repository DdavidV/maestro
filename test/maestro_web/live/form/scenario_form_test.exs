defmodule MaestroWeb.WorkspaceLive.Form.ScenarioFormTest do
  use MaestroWeb.LiveViewCase, async: false

  import Maestro.WorkspaceFixtures

  alias Maestro.Resources

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
  end

  describe "new" do
    test "creating a scenario with one template-step referencing an existing template",
         %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :template, "login_request", %{
        "clients" => ["http"],
        "payload" => %{"username" => "{{username}}"}
      })

      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/scenarios/new")

      view |> element("#resource-path") |> render_change(%{"path" => "login_and_get_token"})
      view |> element("button", "Add step") |> render_click()

      view
      |> element("select[name='steps[_][0][client]']")
      |> render_change(%{"steps" => %{"_" => %{"0" => %{"client" => "http"}}}})

      view |> element(~s{[id="template-picker-_-0"] button}, "Change") |> render_click()

      view
      |> element(
        ~s{[id="template-picker-_-0"] a[phx-value-entry_path="login_request"]},
        "login_request"
      )
      |> render_click()

      {:error, {:live_redirect, %{to: to}}} = view |> element("form") |> render_submit()

      assert to == "/workspace/#{workspace.id}/scenarios/login_and_get_token"

      assert {:ok, %{"steps" => [%{"client" => "http", "template" => "login_request"}]}} =
               Resources.fetch(workspace, :scenario, "login_and_get_token")
    end

    test "adding a scenario-call step and toggling it back to a template step", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/scenarios/new")

      view |> element("button", "Add scenario call") |> render_click()
      html = view |> render()
      assert html =~ "Switch to template step"

      view |> element("button", "Switch to template step") |> render_click()
      html2 = view |> render()
      assert html2 =~ "Switch to scenario call"
    end

    test "adding an assert entry with a JSON expected value", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/scenarios/new")

      view |> element("#resource-path") |> render_change(%{"path" => "with_assert"})
      view |> element("button", "Add step") |> render_click()

      view
      |> element("select[name='steps[_][0][client]']")
      |> render_change(%{"steps" => %{"_" => %{"0" => %{"client" => "http"}}}})

      view
      |> element(~s{[id="template-picker-_-0"] button}, "Change")
      |> render_click()

      view
      |> element(~s{[id="template-picker-_-0"] button}, "Define inline instead")
      |> render_click()

      view
      |> element(~s{[id="template-picker-_-0"] textarea})
      |> render_change(%{"value" => ~s({"clients": ["http"], "payload": {}})})

      view |> element("button", "Add assert") |> render_click()

      view
      |> element("textarea[name='asserts[_][0][0][expected]']")
      |> render_change(%{"asserts" => %{"_" => %{"0" => %{"0" => %{"expected" => "42"}}}}})

      {:error, {:live_redirect, %{to: to}}} = view |> element("form") |> render_submit()

      assert to == "/workspace/#{workspace.id}/scenarios/with_assert"

      assert {:ok, %{"steps" => [%{"assert" => [%{"expected" => 42}]}]}} =
               Resources.fetch(workspace, :scenario, "with_assert")
    end
  end
end
