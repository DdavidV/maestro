defmodule MaestroWeb.WorkspaceLive.Explorer do
  use MaestroWeb, :live_view

  alias Maestro.Core.Runner
  alias Maestro.Resources
  alias MaestroWeb.ResourceComponents

  @kinds [:suite, :scenario, :dataset, :template, :test_plan]
  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:query, "")
     |> stream_configure(:entries, dom_id: &"entry-#{Base.url_encode64(&1.path)}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :dashboard, _params) do
    workspace = socket.assigns.workspace
    counts = Map.new(@kinds, fn kind -> {kind, length(Resources.list(workspace, kind))} end)

    socket
    |> assign(:page_title, workspace.name)
    |> assign(:current_kind, nil)
    |> assign(:current_path, nil)
    |> assign(:counts, counts)
  end

  defp apply_action(socket, :index, %{"kind" => segment} = params) do
    workspace = socket.assigns.workspace

    case ResourceComponents.kind_for_segment(segment) do
      nil ->
        socket
        |> put_flash(:error, "Unknown resource kind #{inspect(segment)}.")
        |> push_navigate(to: "/workspace/#{workspace.id}")

      kind ->
        query = params["query"] || ""
        page = params |> Map.get("page", "1") |> parse_page()
        all_paths = Resources.list_paths(workspace, kind)
        matching_paths = filter_paths(all_paths, query)
        total = length(matching_paths)
        page_paths = matching_paths |> Enum.slice((page - 1) * @page_size, @page_size)
        entries = fetch_entries(workspace, kind, page_paths)

        socket
        |> assign(:page_title, ResourceComponents.kind_label(kind))
        |> assign(:kind, kind)
        |> assign(:segment, segment)
        |> assign(:current_kind, kind)
        |> assign(:current_path, nil)
        |> assign(:query, query)
        |> assign(:page, page)
        |> assign(:total, total)
        |> assign(:page_size, @page_size)
        |> stream(:entries, entries, reset: true)
    end
  end

  defp apply_action(socket, :show, %{"kind" => segment, "path" => path_segments}) do
    workspace = socket.assigns.workspace
    path = Enum.join(path_segments, "/")

    case ResourceComponents.kind_for_segment(segment) do
      nil ->
        socket
        |> put_flash(:error, "Unknown resource kind #{inspect(segment)}.")
        |> push_navigate(to: "/workspace/#{workspace.id}")

      kind ->
        socket =
          socket
          |> assign(:kind, kind)
          |> assign(:segment, segment)
          |> assign(:current_kind, kind)
          |> assign(:current_path, path)
          |> assign(:path, path)

        case Resources.fetch(workspace, kind, path) do
          {:ok, data} ->
            socket
            |> assign(:page_title, data["name"] || path)
            |> assign(:resource, data)
            |> assign(:error, nil)

          {:error, reason} ->
            socket
            |> assign(:page_title, path)
            |> assign(:resource, nil)
            |> assign(:error, reason)
        end
    end
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         "/workspace/#{socket.assigns.workspace.id}/#{socket.assigns.segment}?query=#{URI.encode_www_form(query)}"
     )}
  end

  def handle_event("paginate", %{"page" => page}, socket) do
    %{workspace: workspace, segment: segment, query: query} = socket.assigns

    {:noreply,
     push_patch(socket,
       to:
         "/workspace/#{workspace.id}/#{segment}?page=#{page}&query=#{URI.encode_www_form(query)}"
     )}
  end

  def handle_event("run", _params, socket) do
    %{workspace: workspace, kind: kind, path: path} = socket.assigns

    result =
      case kind do
        :suite -> Runner.run(workspace, [path])
        :test_plan -> Runner.run_test_plan(workspace, path)
      end

    case result do
      {:ok, run_id} ->
        {:noreply, push_navigate(socket, to: "/workspace/#{workspace.id}/history/#{run_id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not start run: #{inspect(reason)}")}
    end
  end

  def handle_event("delete", _params, socket) do
    %{workspace: workspace, kind: kind, segment: segment, path: path} = socket.assigns

    case Resources.delete(workspace, kind, path) do
      :ok ->
        socket
        |> put_flash(:info, "Deleted #{path}.")
        |> push_navigate(to: "/workspace/#{workspace.id}/#{segment}")

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Could not delete #{path}.")
    end
    |> then(&{:noreply, &1})
  end

  defp filter_paths(paths, ""), do: paths

  defp filter_paths(paths, query) do
    query = String.downcase(query)
    Enum.filter(paths, &String.contains?(String.downcase(&1), query))
  end

  defp fetch_entries(workspace, kind, paths) do
    Enum.flat_map(paths, fn path ->
      case Resources.fetch(workspace, kind, path) do
        {:ok, data} ->
          [
            %{
              path: path,
              name: data["name"],
              description: data["description"],
              tags: data["tags"] || []
            }
          ]

        {:error, _reason} ->
          []
      end
    end)
  end

  defp parse_page(value) do
    case Integer.parse(value) do
      {page, _rest} when page > 0 -> page
      _ -> 1
    end
  end
end
