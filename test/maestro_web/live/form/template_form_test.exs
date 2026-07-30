defmodule MaestroWeb.WorkspaceLive.Form.TemplateFormTest do
  use MaestroWeb.LiveViewCase, async: false

  import Maestro.WorkspaceFixtures

  alias Maestro.Resources

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
  end

  describe "new" do
    test "creating a template with a client and payload", %{conn: conn, workspace: workspace} do
      {:ok, view, html} = live(conn, ~p"/workspace/#{workspace.id}/templates/new")

      assert html =~ "http"

      view |> element("#resource-path") |> render_change(%{"path" => "login_request"})

      view
      |> element("input[type=checkbox][phx-value-client=http]")
      |> render_click()

      view
      |> element("textarea[name=payload]")
      |> render_change(%{"payload" => ~s({"username": "{{username}}"})})

      {:error, {:live_redirect, %{to: to}}} = view |> element("form") |> render_submit()

      assert to == "/workspace/#{workspace.id}/templates/login_request"

      assert {:ok, %{"clients" => ["http"], "payload" => %{"username" => "{{username}}"}}} =
               Resources.fetch(workspace, :template, "login_request")
    end

    test "shows an inline error for invalid JSON in payload instead of saving", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/templates/new")

      view |> element("#resource-path") |> render_change(%{"path" => "bad"})

      html =
        view
        |> element("textarea[name=payload]")
        |> render_change(%{"payload" => "{not valid json"})

      assert html =~ "Invalid JSON."
      assert Resources.fetch(workspace, :template, "bad") == {:error, :not_found}
    end
  end

  describe "edit" do
    test "loads existing template data into the form", %{conn: conn, workspace: workspace} do
      resource_fixture!(workspace, :template, "login_request", %{
        "clients" => ["http"],
        "payload" => %{"username" => "{{username}}"}
      })

      {:ok, _view, html} =
        live(conn, ~p"/workspace/#{workspace.id}/templates/edit/login_request")

      assert html =~ "username"
    end
  end
end
