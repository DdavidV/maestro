defmodule MaestroWeb.WorkspaceLiveTest do
  use MaestroWeb.LiveViewCase, async: false

  import Maestro.WorkspaceFixtures

  setup do
    :ok = isolate_workspace_registry!()
    :ok
  end

  describe "index" do
    test "lists registered workspaces and creates a new one", %{conn: conn} do
      workspace = workspace_fixture()

      {:ok, view, html} = live(conn, ~p"/workspaces")
      assert html =~ workspace.name

      root_dir = Path.join(System.tmp_dir!(), "wlive_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(root_dir) end)

      view
      |> element("button", "New workspace")
      |> render_click()

      html =
        view
        |> form("#new-workspace-form", %{"name" => "Brand New", "root_dir" => root_dir})
        |> render_submit()

      assert html =~ "Brand New"
    end

    test "searches workspaces by name", %{conn: conn} do
      root_dir_a = Path.join(System.tmp_dir!(), "wlive_a_#{System.unique_integer([:positive])}")
      root_dir_b = Path.join(System.tmp_dir!(), "wlive_b_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(root_dir_a) end)
      on_exit(fn -> File.rm_rf!(root_dir_b) end)

      {:ok, _} = Maestro.Workspaces.create("Checkout", root_dir_a)
      {:ok, _} = Maestro.Workspaces.create("Performance", root_dir_b)

      {:ok, view, _html} = live(conn, ~p"/workspaces")

      html =
        view
        |> form("#workspace-search-form", %{"query" => "check"})
        |> render_change()

      assert html =~ "Checkout"
      refute html =~ "Performance"
    end

    test "the new workspace form is hidden until the button is clicked", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/workspaces")

      refute html =~ "new-workspace-form"

      html =
        view
        |> element("button", "New workspace")
        |> render_click()

      assert html =~ "new-workspace-form"

      html =
        view
        |> element("button[phx-click=close-new-workspace]")
        |> render_click()

      refute html =~ "new-workspace-form"
    end

    test "closes (unregisters) a workspace", %{conn: conn} do
      workspace = workspace_fixture()

      {:ok, view, _html} = live(conn, ~p"/workspaces")

      html =
        view
        |> element("button[phx-value-id=#{workspace.id}]")
        |> render_click()

      refute html =~ workspace.name
      assert File.dir?(workspace.root_dir), "closing must not delete the directory"
    end
  end

  describe "show" do
    test "renders resource-kind tiles with counts", %{conn: conn} do
      workspace = workspace_fixture()
      resource_fixture!(workspace, :dataset, "a", %{"data" => %{"x" => 1}})

      {:ok, _view, html} = live(conn, ~p"/workspace/#{workspace.id}")

      assert html =~ workspace.name
      assert html =~ "Datasets"
    end
  end

  describe "on_mount redirect" do
    test "an unknown workspace_id redirects to /workspaces with a flash", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/workspaces"}}} =
               live(conn, ~p"/workspace/does-not-exist")
    end
  end
end
