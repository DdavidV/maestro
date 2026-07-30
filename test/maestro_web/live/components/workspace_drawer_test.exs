defmodule MaestroWeb.Components.WorkspaceDrawerTest do
  use MaestroWeb.LiveViewCase, async: false

  import Maestro.WorkspaceFixtures

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
  end

  test "shows every kind's count and auto-expands the current kind's tree", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :suite, "checkout/smoke", %{
      "id" => "smoke",
      "testcases" => [%{"id" => "tc", "steps" => [%{"scenario" => "x", "dataset" => "x"}]}]
    })

    {:ok, view, html} = live(conn, ~p"/workspace/#{workspace.id}/suites/checkout/smoke")

    assert html =~ "Suites"
    render_async(view)
    assert has_element?(view, "nav", "checkout")
    assert has_element?(view, "nav a", "smoke")
  end

  test "collapsing a kind hides its tree, clicking again reopens it", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :dataset, "test_user", %{"data" => %{"a" => 1}})

    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/datasets")
    render_async(view)

    assert has_element?(view, "nav a", "test_user")

    view
    |> element("button[phx-click=toggle-kind][phx-value-kind=dataset]")
    |> render_click()

    refute has_element?(view, "nav a", "test_user")

    view
    |> element("button[phx-click=toggle-kind][phx-value-kind=dataset]")
    |> render_click()

    render_async(view)
    assert has_element?(view, "nav a", "test_user")
  end

  test "a nested folder starts collapsed and expands on click", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :dataset, "checkout/seeded_users", %{"data" => %{"a" => 1}})

    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/datasets")
    render_async(view)

    assert has_element?(view, "nav", "checkout")
    refute has_element?(view, "nav a", "seeded_users")

    view
    |> element("button[phx-click=toggle-folder][phx-value-kind=dataset][phx-value-dir=checkout]")
    |> render_click()

    render_async(view)
    assert has_element?(view, "nav a", "seeded_users")
  end

  test "navigating to a nested resource auto-expands its ancestor folder", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :suite, "checkout/smoke", %{
      "id" => "smoke",
      "testcases" => [%{"id" => "tc", "steps" => [%{"scenario" => "x", "dataset" => "x"}]}]
    })

    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/suites/checkout/smoke")
    render_async(view)

    assert has_element?(view, "nav a", "smoke")
  end

  test "expanded kinds/folders survive clicking between different resources (patch, not remount)",
       %{conn: conn, workspace: workspace} do
    resource_fixture!(workspace, :suite, "checkout/smoke", %{
      "id" => "smoke",
      "testcases" => [%{"id" => "tc", "steps" => [%{"scenario" => "x", "dataset" => "x"}]}]
    })

    resource_fixture!(workspace, :dataset, "checkout/seeded_users", %{"data" => %{"a" => 1}})

    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/suites")
    render_async(view)

    # Suites is auto-expanded (current kind), but its "checkout" folder
    # isn't (no current_path on the index page) expand it so "smoke" is
    # clickable in the drawer.
    view
    |> element("button[phx-click=toggle-folder][phx-value-kind=suite][phx-value-dir=checkout]")
    |> render_click()

    render_async(view)

    # Manually expand a kind (Datasets) and a nested folder that isn't the
    # current page's own kind/path, the state we're proving survives.
    view
    |> element("button[phx-click=toggle-kind][phx-value-kind=dataset]")
    |> render_click()

    render_async(view)

    view
    |> element("button[phx-click=toggle-folder][phx-value-kind=dataset][phx-value-dir=checkout]")
    |> render_click()

    render_async(view)
    assert has_element?(view, "nav a", "seeded_users")

    # Click into a suite (a `patch`, same LiveView process) the drawer's
    # LiveComponent instance must be the same one, so its expansion state
    # (Datasets/checkout, unrelated to the page we're navigating to) must
    # still be there afterward.
    view
    |> element("nav a", "smoke")
    |> render_click()

    assert_patch(view, ~p"/workspace/#{workspace.id}/suites/checkout/smoke")
    render_async(view)
    assert has_element?(view, "nav a", "seeded_users")
  end

  test "a directory with hundreds of entries streams all of them, none dropped", %{
    conn: conn,
    workspace: workspace
  } do
    for i <- 1..210 do
      resource_fixture!(workspace, :dataset, "d_#{String.pad_leading("#{i}", 4, "0")}", %{
        "data" => %{"a" => i}
      })
    end

    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/datasets")
    render_async(view)

    assert has_element?(view, "nav a", "d_0001")
    assert has_element?(view, "nav a", "d_0210")
  end

  test "opening one folder does not load a sibling folder's contents", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :dataset, "checkout/seeded_users", %{"data" => %{"a" => 1}})
    resource_fixture!(workspace, :dataset, "accounts/seeded_admins", %{"data" => %{"a" => 1}})

    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/datasets")
    render_async(view)

    view
    |> element("button[phx-click=toggle-folder][phx-value-kind=dataset][phx-value-dir=checkout]")
    |> render_click()

    render_async(view)
    assert has_element?(view, "nav a", "seeded_users")
    refute has_element?(view, "nav a", "seeded_admins")
  end

  test "shows a loading indicator for a directory while its listing is still in flight", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :dataset, "test_user", %{"data" => %{"a" => 1}})

    {:ok, view, html} = live(conn, ~p"/workspace/#{workspace.id}/datasets")

    assert html =~ "Loading..."
    render_async(view)
    refute view |> render() =~ "Loading..."
  end
end
