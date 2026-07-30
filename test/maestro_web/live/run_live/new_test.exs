defmodule MaestroWeb.RunLive.NewTest do
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

  test "lists suites and test plans, searchable independently", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))
    resource_fixture!(workspace, :suite, "accounts/login", suite("accounts-login"))

    resource_fixture!(workspace, :test_plan, "nightly", %{
      "id" => "nightly",
      "test_suites" => ["checkout/smoke"]
    })

    {:ok, view, html} = live(conn, ~p"/workspace/#{workspace.id}/run")

    assert html =~ "checkout/smoke"
    assert html =~ "accounts/login"
    assert html =~ "nightly"

    view |> form("#suite-search-form", %{"query" => "checkout"}) |> render_change()

    assert has_element?(view, "input[phx-value-path='checkout/smoke']")
    refute has_element?(view, "input[phx-value-path='accounts/login']")
  end

  test "selecting suites across a search accumulates in the Selected panel", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))
    resource_fixture!(workspace, :suite, "accounts/login", suite("accounts-login"))

    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/run")

    view
    |> element("input[phx-value-kind=suite][phx-value-path='checkout/smoke']")
    |> render_click()

    view |> form("#suite-search-form", %{"query" => "accounts"}) |> render_change()

    view
    |> element("input[phx-value-kind=suite][phx-value-path='accounts/login']")
    |> render_click()

    html = render(view)
    assert html =~ "Selected (2)"
    assert html =~ "checkout/smoke"
    assert html =~ "accounts/login"
  end

  test "unselecting via the Selected panel removes just that item", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))
    resource_fixture!(workspace, :suite, "accounts/login", suite("accounts-login"))

    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/run")

    view
    |> element("input[phx-value-kind=suite][phx-value-path='checkout/smoke']")
    |> render_click()

    view
    |> element("input[phx-value-kind=suite][phx-value-path='accounts/login']")
    |> render_click()

    view
    |> element(
      "button[phx-click=toggle-selected][phx-value-kind=suite][phx-value-path='checkout/smoke']"
    )
    |> render_click()

    html = render(view)
    assert html =~ "Selected (1)"
    refute html =~ "Selected (2)"
  end

  test "Run selected is disabled with nothing selected", %{conn: conn, workspace: workspace} do
    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/run")

    assert has_element?(view, "button[phx-click=run-selected][disabled]")
  end

  test "running a mix of a suite and a test plan starts one run covering both, deduplicated", %{
    conn: conn,
    workspace: workspace
  } do
    resource_fixture!(workspace, :suite, "checkout/smoke", suite("checkout-smoke"))
    resource_fixture!(workspace, :suite, "accounts/login", suite("accounts-login"))

    resource_fixture!(workspace, :test_plan, "nightly", %{
      "id" => "nightly",
      "test_suites" => ["checkout/smoke", "accounts/login"]
    })

    {:ok, view, _html} = live(conn, ~p"/workspace/#{workspace.id}/run")

    view
    |> element("input[phx-value-kind=suite][phx-value-path='checkout/smoke']")
    |> render_click()

    view
    |> element("input[phx-value-kind=test_plan][phx-value-path=nightly]")
    |> render_click()

    assert {:error, {:live_redirect, %{to: to}}} =
             view |> element("button", "Run selected (2)") |> render_click()

    assert to =~ ~r{^/workspace/#{workspace.id}/history/run_}

    run_id = to |> String.split("/") |> List.last()
    wait_until_done(run_id)

    {:ok, result} = Runner.result(run_id)
    assert Enum.map(result.suites, & &1.id) == ["checkout-smoke", "accounts-login"]
  end
end
