defmodule MaestroWeb.Components.WorkspaceDrawer do
  @moduledoc """
  Left-hand sidebar shown on every workspace-scoped page: one expandable
  section per resource kind (Suites/Scenarios/Datasets/Templates/Test
  Plans), each rendering that kind's resources as a nested folder tree.
  """

  use MaestroWeb, :live_component

  alias Maestro.Resources

  @impl true
  def update(
        %{workspace: workspace, current_kind: current_kind, current_path: current_path},
        socket
      ) do
    open_kinds = Map.get(socket.assigns, :open_kinds) || MapSet.new([current_kind])

    open_dirs =
      Map.get(socket.assigns, :open_dirs) || initial_open_dirs(current_kind, current_path)

    counts =
      Map.new(resource_tiles(), fn {kind, _label, _segment} -> {kind, count(workspace, kind)} end)

    socket =
      socket
      |> assign(:workspace, workspace)
      |> assign(:current_kind, current_kind)
      |> assign(:current_path, current_path)
      |> assign(:counts, counts)
      |> assign(:open_kinds, open_kinds)
      |> assign(:open_dirs, open_dirs)
      |> assign_new(:folders_by_dir, fn -> %{} end)
      |> assign_new(:loaded_dirs, fn -> MapSet.new() end)
      |> assign_new(:configured_streams, fn -> MapSet.new() end)

    dir_keys = open_kinds |> MapSet.delete(nil) |> Enum.map(&{&1, ""}) |> Enum.concat(open_dirs)

    {:ok, ensure_loaded(socket, dir_keys)}
  end

  defp count(workspace, kind), do: length(Resources.list_paths(workspace, kind))

  # Kicks off an async load for every {kind, dir_path} not already loaded
  # or in flight, tracked via `loaded_dirs` so re-entrant calls (e.g. every
  # `update/2` on navigation) don't re-fetch a directory that's already
  # resolved or already being fetched.
  defp ensure_loaded(socket, dir_keys) do
    Enum.reduce(dir_keys, socket, fn {kind, dir_path} = key, socket ->
      if MapSet.member?(socket.assigns.loaded_dirs, key) do
        socket
      else
        workspace = socket.assigns.workspace
        name = stream_name(key)

        socket =
          if MapSet.member?(socket.assigns.configured_streams, name) do
            socket
          else
            socket
            |> update(:configured_streams, &MapSet.put(&1, name))
            |> stream_configure(name,
              dom_id: &"drawer-entry-#{kind}-#{Base.url_encode64(&1.path)}"
            )
          end

        socket
        |> update(:loaded_dirs, &MapSet.put(&1, key))
        |> stream(name, [])
        |> start_async({:load_dir, kind, dir_path}, fn ->
          {kind, dir_path, Resources.list_dir(workspace, kind, dir_path)}
        end)
      end
    end)
  end

  @impl true
  def handle_async({:load_dir, kind, dir_path}, {:ok, {kind, dir_path, listing}}, socket) do
    socket =
      socket
      |> update(:folders_by_dir, &Map.put(&1, {kind, dir_path}, listing.folders))
      |> stream(stream_name({kind, dir_path}), listing.entries)

    {:noreply, socket}
  end

  def handle_async({:load_dir, _kind, _dir_path}, {:exit, _reason}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle-kind", %{"kind" => kind}, socket) do
    kind = String.to_existing_atom(kind)
    open_kinds = toggle(socket.assigns.open_kinds, kind)

    socket =
      if MapSet.member?(open_kinds, kind) do
        ensure_loaded(socket, [{kind, ""}])
      else
        collapse_dir(socket, kind, "")
      end

    {:noreply, assign(socket, :open_kinds, open_kinds)}
  end

  def handle_event("toggle-folder", %{"kind" => kind, "dir" => dir_path}, socket) do
    kind = String.to_existing_atom(kind)
    key = {kind, dir_path}
    now_open? = not MapSet.member?(socket.assigns.open_dirs, key)
    open_dirs = toggle(socket.assigns.open_dirs, key)

    socket =
      if now_open? do
        ensure_loaded(socket, [key])
      else
        collapse_dir(socket, kind, dir_path)
      end

    {:noreply, assign(socket, :open_dirs, open_dirs)}
  end

  defp collapse_dir(socket, kind, dir_path) do
    key = {kind, dir_path}
    folders = socket.assigns.folders_by_dir[key] || []

    socket =
      Enum.reduce(folders, socket, fn folder, socket ->
        collapse_dir(socket, kind, Path.join(dir_path, folder))
      end)

    socket
    |> stream(stream_name(key), [], reset: true)
    |> update(:loaded_dirs, &MapSet.delete(&1, key))
    |> update(:folders_by_dir, &Map.delete(&1, key))
  end

  defp initial_open_dirs(_current_kind, nil), do: MapSet.new()

  defp initial_open_dirs(current_kind, current_path) do
    current_path
    |> String.split("/")
    |> List.pop_at(-1)
    |> elem(1)
    |> Enum.scan(&Path.join(&2, &1))
    |> Enum.map(&{current_kind, &1})
    |> MapSet.new()
    |> MapSet.put({current_kind, ""})
  end

  defp toggle(set, item) do
    if MapSet.member?(set, item), do: MapSet.delete(set, item), else: MapSet.put(set, item)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <nav aria-label="Workspace resources" class="space-y-0.5">
      <div :for={{kind, label, segment} <- resource_tiles()}>
        <div class={[
          "group flex items-center rounded-field transition-colors hover:bg-base-200",
          @current_kind == kind && is_nil(@current_path) && "bg-base-200"
        ]}>
          <button
            type="button"
            phx-click="toggle-kind"
            phx-value-kind={kind}
            phx-target={@myself}
            aria-expanded={to_string(MapSet.member?(@open_kinds, kind))}
            class="flex min-w-0 flex-1 cursor-pointer items-center gap-2 py-1.5 pl-1.5 pr-1 text-sm font-medium text-base-content/80"
          >
            <.icon
              name="hero-chevron-right-mini"
              class={[
                "size-4 shrink-0 text-base-content/40 transition-transform",
                MapSet.member?(@open_kinds, kind) && "rotate-90"
              ]}
            />
            <.icon name={kind_icon(kind)} class="size-4 shrink-0 text-base-content/50" />
            <span class="flex-1 truncate text-left">{label}</span>
          </button>
          <.link
            patch={"/workspace/#{@workspace.id}/#{segment}"}
            class="mr-1 rounded px-1.5 py-0.5 text-xs tabular-nums text-base-content/40 hover:bg-base-300 hover:text-base-content"
            title={"Browse all #{String.downcase(label)}"}
            aria-label={"Browse all #{String.downcase(label)}"}
          >
            {@counts[kind]}
          </.link>
        </div>

        <div
          :if={MapSet.member?(@open_kinds, kind)}
          class="ml-[1.0625rem] border-l border-base-300 pl-1.5 py-0.5"
        >
          <.dir_node
            kind={kind}
            dir_path=""
            segment={segment}
            workspace={@workspace}
            loaded_dirs={@loaded_dirs}
            folders_by_dir={@folders_by_dir}
            open_dirs={@open_dirs}
            current_kind={@current_kind}
            current_path={@current_path}
            streams={@streams}
            myself={@myself}
          />
        </div>
      </div>
    </nav>
    """
  end

  attr :kind, :atom, required: true
  attr :dir_path, :string, required: true
  attr :segment, :string, required: true
  attr :workspace, :any, required: true
  attr :loaded_dirs, :any, required: true
  attr :folders_by_dir, :map, required: true
  attr :open_dirs, :any, required: true
  attr :current_kind, :atom, required: true
  attr :current_path, :any, required: true
  attr :streams, :any, required: true
  attr :myself, :any, required: true

  defp dir_node(assigns) do
    key = {assigns.kind, assigns.dir_path}
    folders = assigns.folders_by_dir[key]
    loading? = is_nil(folders) and MapSet.member?(assigns.loaded_dirs, key)
    entries = Map.get(assigns.streams, stream_name(key))

    assigns =
      assign(assigns,
        folders: folders || [],
        loading?: loading?,
        entries: entries
      )

    ~H"""
    <div>
      <p :if={@loading?} class="flex items-center gap-1.5 px-2 py-1 text-xs text-base-content/50">
        <.icon name="hero-arrow-path" class="size-3 animate-spin" /> Loading...
      </p>

      <div :for={folder <- @folders}>
        <button
          type="button"
          phx-click="toggle-folder"
          phx-value-kind={@kind}
          phx-value-dir={Path.join(@dir_path, folder)}
          phx-target={@myself}
          class="tree-item cursor-pointer"
        >
          <.icon
            name={
              if MapSet.member?(@open_dirs, {@kind, Path.join(@dir_path, folder)}),
                do: "hero-folder-open-mini",
                else: "hero-folder-mini"
            }
            class="size-4 shrink-0 text-base-content/40"
          />
          <span class="truncate">{folder}</span>
        </button>

        <div
          :if={MapSet.member?(@open_dirs, {@kind, Path.join(@dir_path, folder)})}
          class="ml-[0.9375rem] border-l border-base-300 pl-1.5"
        >
          <.dir_node
            kind={@kind}
            dir_path={Path.join(@dir_path, folder)}
            segment={@segment}
            workspace={@workspace}
            loaded_dirs={@loaded_dirs}
            folders_by_dir={@folders_by_dir}
            open_dirs={@open_dirs}
            current_kind={@current_kind}
            current_path={@current_path}
            streams={@streams}
            myself={@myself}
          />
        </div>
      </div>

      <div :if={@entries} id={"dir-entries-#{@kind}-#{dir_dom_id(@dir_path)}"} phx-update="stream">
        <.link
          :for={{dom_id, entry} <- @entries}
          id={dom_id}
          patch={"/workspace/#{@workspace.id}/#{@segment}/#{entry.path}"}
          class={[
            "tree-item",
            @kind == @current_kind && entry.path == @current_path && "tree-item-active"
          ]}
          title={entry.path}
        >
          <span class="truncate">{Path.basename(entry.path)}</span>
        </.link>
      </div>
    </div>
    """
  end

  defp dir_dom_id(""), do: "root"
  defp dir_dom_id(dir_path), do: Base.url_encode64(dir_path, padding: false)

  defp stream_name({kind, dir_path}),
    do: :"dir__#{kind}__#{Base.url_encode64(dir_path, padding: false)}"
end
