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

  attr :kind, :atom, required: true
  attr :title, :string, required: true
  attr :query, :string, required: true
  attr :paths, :list, required: true
  attr :page, :integer, required: true
  attr :total, :integer, required: true
  attr :page_size, :integer, required: true
  attr :selected, :any, required: true

  defp picker_section(assigns) do
    ~H"""
    <section class="panel overflow-hidden">
      <div class="flex flex-wrap items-center gap-3 border-b border-base-300 px-4 py-3">
        <.icon name={kind_icon(@kind)} class="size-4 text-base-content/40" />
        <h3 class="text-sm font-semibold">
          {@title} <span class="ml-1 font-normal text-base-content/50">{@total}</span>
        </h3>
        <form
          id={"#{@kind}-search-form"}
          phx-change={"search-#{@kind}"}
          class="ml-auto w-full sm:w-64"
          onsubmit="return false"
        >
          <label class="input input-sm w-full">
            <.icon name="hero-magnifying-glass-mini" class="size-4 text-base-content/40" />
            <input
              type="text"
              name="query"
              value={@query}
              placeholder={"Filter #{String.downcase(@title)}…"}
              phx-debounce="200"
              autocomplete="off"
            />
          </label>
        </form>
      </div>

      <ul class="max-h-[22rem] divide-y divide-base-300 overflow-y-auto">
        <li :for={path <- @paths}>
          <label class={[
            "flex cursor-pointer items-center gap-3 px-4 py-2.5 transition-colors",
            if(MapSet.member?(@selected, {@kind, path}),
              do: "bg-primary/5 hover:bg-primary/10",
              else: "hover:bg-base-200/60"
            )
          ]}>
            <input
              type="checkbox"
              checked={MapSet.member?(@selected, {@kind, path})}
              phx-click="toggle-selected"
              phx-value-kind={@kind}
              phx-value-path={path}
              class="checkbox checkbox-sm checkbox-primary"
            />
            <span class="kbd-path truncate">{path}</span>
          </label>
        </li>
        <li :if={@paths == []} class="px-4 py-8 text-center text-sm text-base-content/50">
          No {String.downcase(@title)} found.
        </li>
      </ul>

      <div
        :if={@total > @page_size}
        class="flex items-center justify-between gap-2 border-t border-base-300 px-4 py-2.5"
      >
        <span class="text-xs text-base-content/60">
          Page {@page} of {max(ceil(@total / @page_size), 1)} ({@total} total)
        </span>
        <div class="flex gap-2">
          <.button disabled={@page <= 1} phx-click={"paginate-#{@kind}"} phx-value-page={@page - 1}>
            <.icon name="hero-chevron-left-mini" class="size-4" /> Previous
          </.button>
          <.button
            disabled={@page * @page_size >= @total}
            phx-click={"paginate-#{@kind}"}
            phx-value-page={@page + 1}
          >
            Next <.icon name="hero-chevron-right-mini" class="size-4" />
          </.button>
        </div>
      </div>
    </section>
    """
  end

  defp parse_page(value) do
    case Integer.parse(value) do
      {page, _rest} when page > 0 -> page
      _ -> 1
    end
  end
end
