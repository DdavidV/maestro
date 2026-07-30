defmodule MaestroWeb.WorkspaceLive.Form.DatasetFormTest do
  use MaestroWeb.LiveViewCase, async: false

  import Maestro.WorkspaceFixtures

  alias Maestro.Resources

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
  end

  describe "new" do
    test "creating a dataset with a data field", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/datasets/new")

      view |> element("#resource-path") |> render_change(%{"path" => "test_user"})
      view |> element("button", "Add field") |> render_click()

      view
      |> element("input[name='data_pairs[0][key]']")
      |> render_change(%{"data_pairs" => %{"0" => %{"key" => "username"}}})

      view
      |> element("input[name='data_pairs[0][value]']")
      |> render_change(%{"data_pairs" => %{"0" => %{"value" => "alice"}}})

      {:error, {:live_redirect, %{to: to}}} =
        view |> element("form") |> render_submit()

      assert to == "/workspace/#{workspace.id}/datasets/test_user"

      assert {:ok, %{"data" => %{"username" => "alice"}}} =
               Resources.fetch(workspace, :dataset, "test_user")
    end

    test "shows a path error when saving with a blank path", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/datasets/new")

      html = view |> element("form") |> render_submit()

      assert html =~ "Path can&#39;t be blank."
    end

    test "shows validation errors instead of saving when data is invalid", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/datasets/new")

      view |> element("#resource-path") |> render_change(%{"path" => "empty_dataset"})

      html = view |> element("form") |> render_submit()

      assert html =~ "schemata"
      assert Resources.fetch(workspace, :dataset, "empty_dataset") == {:error, :not_found}
    end

    test "the 'Add row' button is disabled until at least one column exists", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/datasets/new")

      view
      |> element("button[phx-click=dataset-set-mode][phx-value-mode=rows]")
      |> render_click()

      assert has_element?(view, "button[phx-click=dataset-add-row][disabled]")

      view |> element("button", "Add column") |> render_click()

      refute has_element?(view, "button[phx-click=dataset-add-row][disabled]")
    end

    test "adding and filling a rows column, then a row", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/datasets/new")

      view |> element("#resource-path") |> render_change(%{"path" => "seeded_users"})

      view
      |> element("button[phx-click=dataset-set-mode][phx-value-mode=rows]")
      |> render_click()

      view |> element("button", "Add column") |> render_click()

      view
      |> element("input[name='row_columns[0]']")
      |> render_change(%{"row_columns" => %{"0" => "username"}})

      view |> element("button", "Add row") |> render_click()

      view
      |> element("input[name='rows[0][username]']")
      |> render_change(%{"rows" => %{"0" => %{"username" => "alice"}}})

      {:error, {:live_redirect, %{to: to}}} =
        view |> element("form") |> render_submit()

      assert to == "/workspace/#{workspace.id}/datasets/seeded_users"

      assert {:ok, %{"rows" => [%{"username" => "alice"}]}} =
               Resources.fetch(workspace, :dataset, "seeded_users")
    end

    test "switching from data mode to rows mode clears the data fields already filled in", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/datasets/new")

      view |> element("#resource-path") |> render_change(%{"path" => "test_user"})
      view |> element("button", "Add field") |> render_click()

      view
      |> element("input[name='data_pairs[0][key]']")
      |> render_change(%{"data_pairs" => %{"0" => %{"key" => "username"}}})

      view
      |> element("button[phx-click=dataset-set-mode][phx-value-mode=rows]")
      |> render_click()

      view
      |> element("button[phx-click=dataset-set-mode][phx-value-mode=data]")
      |> render_click()

      html = view |> render()
      refute html =~ ~s(value="username")

      view |> element("button", "Add field") |> render_click()

      view
      |> element("input[name='data_pairs[0][key]']")
      |> render_change(%{"data_pairs" => %{"0" => %{"key" => "email"}}})

      view
      |> element("input[name='data_pairs[0][value]']")
      |> render_change(%{"data_pairs" => %{"0" => %{"value" => "alice@example.com"}}})

      {:error, {:live_redirect, _}} = view |> element("form") |> render_submit()

      assert {:ok, data} = Resources.fetch(workspace, :dataset, "test_user")
      refute Map.has_key?(data, "rows")
      assert data["data"] == %{"email" => "alice@example.com"}
    end
  end

  describe "edit" do
    test "loads existing data and saves changes back to the same path", %{
      conn: conn,
      workspace: workspace
    } do
      resource_fixture!(workspace, :dataset, "test_user", %{
        "data" => %{"username" => "alice"}
      })

      {:ok, view, html} = live(conn, ~p"/workspace/#{workspace.id}/datasets/edit/test_user")

      assert html =~ "alice"

      view
      |> element("input[name='data_pairs[0][value]']")
      |> render_change(%{"data_pairs" => %{"0" => %{"value" => "bob"}}})

      {:error, {:live_redirect, %{to: to}}} =
        view |> element("form") |> render_submit()

      assert to == "/workspace/#{workspace.id}/datasets/test_user"

      assert {:ok, %{"data" => %{"username" => "bob"}}} =
               Resources.fetch(workspace, :dataset, "test_user")
    end
  end
end
