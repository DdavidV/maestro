defmodule MaestroWeb.RunLive.New do
  @moduledoc """
  Picks any combination of suites and/or test plans to run together as
  one run: `/workspace/:workspace_id/run`.

  A selected test plan is expanded to its own `test_suites` at run time
  (`flatten_selection/2`) and merged with directly-selected suite paths
  (deduplicated) so a mixed selection becomes exactly one `Runner.run/2`
  call, one `run_id`, not one run per selected item.
  """

  use MaestroWeb, :live_view

  alias Maestro.Core.Runner
  alias Maestro.Resources

  @page_size 20

  @impl true
  def mount(_params, _session, socket) do
    workspace = socket.assigns.workspace

    {:ok,
     socket
     |> assign(:page_title, "Run")
     |> assign(:current_kind, nil)
     |> assign(:current_path, nil)
     |> assign(:selected, MapSet.new())
     |> assign(:suite_query, "")
     |> assign(:suite_page, 1)
     |> assign(:test_plan_query, "")
     |> assign(:test_plan_page, 1)
     |> assign_section(workspace, :suite)
     |> assign_section(workspace, :test_plan)}
  end

  defp assign_section(socket, workspace, kind) do
    query = Map.fetch!(socket.assigns, :"#{kind}_query")
    page = Map.fetch!(socket.assigns, :"#{kind}_page")

    all_paths = Resources.list_paths(workspace, kind)
    matching_paths = filter_paths(all_paths, query)
    total = length(matching_paths)
    page_paths = Enum.slice(matching_paths, (page - 1) * @page_size, @page_size)

    socket
    |> assign(:"#{kind}_total", total)
    |> assign(:"#{kind}_page_size", @page_size)
    |> assign(:"#{kind}_paths", page_paths)
  end

  defp filter_paths(paths, ""), do: paths

  defp filter_paths(paths, query) do
    query = String.downcase(query)
    Enum.filter(paths, &String.contains?(String.downcase(&1), query))
  end

  @impl true
  def handle_event("search-suite", %{"query" => query}, socket) do
    socket = socket |> assign(:suite_query, query) |> assign(:suite_page, 1)
    {:noreply, assign_section(socket, socket.assigns.workspace, :suite)}
  end

  def handle_event("search-test_plan", %{"query" => query}, socket) do
    socket = socket |> assign(:test_plan_query, query) |> assign(:test_plan_page, 1)
    {:noreply, assign_section(socket, socket.assigns.workspace, :test_plan)}
  end

  def handle_event("paginate-suite", %{"page" => page}, socket) do
    socket = assign(socket, :suite_page, parse_page(page))
    {:noreply, assign_section(socket, socket.assigns.workspace, :suite)}
  end

  def handle_event("paginate-test_plan", %{"page" => page}, socket) do
    socket = assign(socket, :test_plan_page, parse_page(page))
    {:noreply, assign_section(socket, socket.assigns.workspace, :test_plan)}
  end

  def handle_event("toggle-selected", %{"kind" => kind, "path" => path}, socket) do
    key = {String.to_existing_atom(kind), path}

    selected =
      if MapSet.member?(socket.assigns.selected, key) do
        MapSet.delete(socket.assigns.selected, key)
      else
        MapSet.put(socket.assigns.selected, key)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("clear-selected", _params, socket) do
    {:noreply, assign(socket, :selected, MapSet.new())}
  end

  def handle_event("run-selected", _params, socket) do
    workspace = socket.assigns.workspace
    suite_paths = flatten_selection(workspace, socket.assigns.selected)

    case suite_paths do
      [] ->
        {:noreply, put_flash(socket, :error, "Select at least one suite or test plan first.")}

      paths ->
        case Runner.run(workspace, paths) do
          {:ok, run_id} ->
            {:noreply, push_navigate(socket, to: "/workspace/#{workspace.id}/history/#{run_id}")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Could not start run: #{inspect(reason)}")}
        end
    end
  end

  defp flatten_selection(workspace, selected) do
    selected
    |> Enum.flat_map(fn
      {:suite, path} ->
        [path]

      {:test_plan, path} ->
        case Resources.fetch(workspace, :test_plan, path) do
          {:ok, %{"test_suites" => test_suites}} -> test_suites
          {:error, _reason} -> []
        end
    end)
    |> Enum.uniq()
  end

  defp parse_page(value) do
    case Integer.parse(value) do
      {page, _rest} when page > 0 -> page
      _ -> 1
    end
  end
end
