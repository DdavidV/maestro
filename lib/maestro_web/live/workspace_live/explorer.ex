defmodule MaestroWeb.WorkspaceLive.Explorer do

  use MaestroWeb, :live_view

  alias Maestro.Resources
  alias MaestroWeb.ResourceComponents

  @kinds [:suite, :scenario, :dataset, :template, :test_plan]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :query, "")}
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

  defp apply_action(socket, :index, %{"kind" => segment}) do
    workspace = socket.assigns.workspace

    case ResourceComponents.kind_for_segment(segment) do
      nil ->
        socket
        |> put_flash(:error, "Unknown resource kind #{inspect(segment)}.")
        |> push_navigate(to: "/workspace/#{workspace.id}")

      kind ->
        entries = Resources.list(workspace, kind)

        socket
        |> assign(:page_title, ResourceComponents.kind_label(kind))
        |> assign(:kind, kind)
        |> assign(:segment, segment)
        |> assign(:current_kind, kind)
        |> assign(:current_path, nil)
        |> assign(:query, "")
        |> assign(:entries, entries)
        |> assign(:filtered, entries)
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
    filtered = filter(socket.assigns.entries, socket.assigns.kind, query)
    {:noreply, socket |> assign(:query, query) |> assign(:filtered, filtered)}
  end

  defp filter(entries, _kind, ""), do: entries

  defp filter(entries, kind, query) do
    query = String.downcase(query)

    Enum.filter(entries, fn entry ->
      String.contains?(String.downcase(entry.path), query) or
        String.contains?(String.downcase(entry.name || ""), query) or
        (kind == :suite and Enum.any?(entry.tags, &String.contains?(String.downcase(&1), query)))
    end)
  end
end
