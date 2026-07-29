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
    entries =
      Map.new(resource_tiles(), fn {kind, _label, _segment} ->
        {kind, Resources.list(workspace, kind)}
      end)

    {:ok,
     socket
     |> assign(:workspace, workspace)
     |> assign(:current_kind, current_kind)
     |> assign(:current_path, current_path)
     |> assign(:entries, entries)
     |> assign_new(:open_kinds, fn -> MapSet.new([current_kind]) end)
     |> assign_new(:open_folders, fn -> initial_open_folders(current_kind, current_path) end)}
  end

  @impl true
  def handle_event("toggle-kind", %{"kind" => kind}, socket) do
    kind = String.to_existing_atom(kind)
    open_kinds = toggle(socket.assigns.open_kinds, kind)
    {:noreply, assign(socket, :open_kinds, open_kinds)}
  end

  def handle_event("toggle-folder", %{"key" => key}, socket) do
    open_folders = toggle(socket.assigns.open_folders, key)
    {:noreply, assign(socket, :open_folders, open_folders)}
  end

  defp initial_open_folders(_current_kind, nil), do: MapSet.new()

  defp initial_open_folders(current_kind, current_path) do
    segments = String.split(current_path, "/")
    ancestor_dirs = segments |> List.pop_at(-1) |> elem(1)

    ancestor_dirs
    |> Enum.scan(&Path.join(&2, &1))
    |> Enum.map(&"#{current_kind}/#{&1}")
    |> MapSet.new()
  end

  defp toggle(set, item) do
    if MapSet.member?(set, item), do: MapSet.delete(set, item), else: MapSet.put(set, item)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <nav class="w-64 shrink-0 h-full overflow-y-auto border-r border-base-300 bg-base-100 px-2 py-3">
      <.link
        patch={"/workspace/#{@workspace.id}"}
        class="block px-2 py-1.5 mb-2 rounded font-semibold text-sm hover:bg-base-200"
      >
        {@workspace.name}
      </.link>

      <div :for={{kind, label, segment} <- resource_tiles()} class="mb-1">
        <button
          type="button"
          phx-click="toggle-kind"
          phx-value-kind={kind}
          phx-target={@myself}
          class="w-full flex items-center gap-1 px-2 py-1 rounded text-sm font-medium hover:bg-base-200"
        >
          <.icon
            name={
              if MapSet.member?(@open_kinds, kind),
                do: "hero-chevron-down",
                else: "hero-chevron-right"
            }
            class="size-3.5 shrink-0"
          />
          <span class="flex-1 text-left">{label}</span>
          <span class="text-xs text-base-content/50">{length(@entries[kind])}</span>
        </button>

        <div :if={MapSet.member?(@open_kinds, kind)} class="ml-2">
          <.tree_node
            node={build_tree(@entries[kind])}
            kind={kind}
            segment={segment}
            key_prefix={to_string(kind)}
            workspace={@workspace}
            open_folders={@open_folders}
            current_kind={@current_kind}
            current_path={@current_path}
            myself={@myself}
          />
        </div>
      </div>
    </nav>
    """
  end

  attr :node, :map, required: true
  attr :kind, :atom, required: true
  attr :segment, :string, required: true
  attr :key_prefix, :string, required: true
  attr :workspace, :any, required: true
  attr :open_folders, :any, required: true
  attr :current_kind, :atom, required: true
  attr :current_path, :any, required: true
  attr :myself, :any, required: true

  defp tree_node(assigns) do
    folders = assigns.node.folders |> Map.keys() |> Enum.sort()
    leaves = assigns.node.leaves |> Enum.sort_by(& &1.path)

    assigns = assign(assigns, folders: folders, leaves: leaves)

    ~H"""
    <div>
      <div :for={folder <- @folders}>
        <button
          type="button"
          phx-click="toggle-folder"
          phx-value-key={"#{@key_prefix}/#{folder}"}
          phx-target={@myself}
          class="w-full flex items-center gap-1 px-2 py-1 rounded text-sm hover:bg-base-200"
        >
          <.icon
            name={
              if MapSet.member?(@open_folders, "#{@key_prefix}/#{folder}"),
                do: "hero-chevron-down",
                else: "hero-chevron-right"
            }
            class="size-3.5 shrink-0"
          />
          <.icon name="hero-folder" class="size-3.5 shrink-0 text-base-content/50" />
          <span>{folder}</span>
        </button>

        <div
          :if={MapSet.member?(@open_folders, "#{@key_prefix}/#{folder}")}
          class="ml-3 border-l border-base-300 pl-1"
        >
          <.tree_node
            node={@node.folders[folder]}
            kind={@kind}
            segment={@segment}
            key_prefix={"#{@key_prefix}/#{folder}"}
            workspace={@workspace}
            open_folders={@open_folders}
            current_kind={@current_kind}
            current_path={@current_path}
            myself={@myself}
          />
        </div>
      </div>

      <.link
        :for={entry <- @leaves}
        patch={"/workspace/#{@workspace.id}/#{@segment}/#{entry.path}"}
        class={[
          "flex items-center gap-1 px-2 py-1 rounded text-sm hover:bg-base-200",
          @kind == @current_kind && entry.path == @current_path && "bg-base-200 font-semibold"
        ]}
      >
        <.icon name="hero-document-text" class="size-3.5 shrink-0 text-base-content/50" />
        <span class="truncate">{Path.basename(entry.path)}</span>
      </.link>
    </div>
    """
  end

  defp build_tree(entries) do
    Enum.reduce(entries, %{folders: %{}, leaves: []}, fn entry, tree ->
      insert(tree, String.split(entry.path, "/"), entry)
    end)
  end

  defp insert(tree, [_last], entry) do
    %{tree | leaves: [entry | tree.leaves]}
  end

  defp insert(tree, [segment | rest], entry) do
    subtree = Map.get(tree.folders, segment, %{folders: %{}, leaves: []})
    %{tree | folders: Map.put(tree.folders, segment, insert(subtree, rest, entry))}
  end
end
