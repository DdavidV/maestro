defmodule MaestroWeb.Components.ReferencePicker do
  @moduledoc """
  The shared "pick an existing dataset/template/scenario by path, or
  define inline" control needed everywhere `step.schema.json` allows a
  `oneOf: [ref-string, inline-body]` (a step's `template`/`dataset`/
  `scenario`, a scenario's `default_dataset`).

  A `Phoenix.LiveComponent` so its own live-filtered search text/open state
  is self-contained, but it never mutates `@data` itself (it doesn't know
  where in the parent LiveView's `@data` tree its value lives, only its own
  `path` for addressing). Instead it `send/2`s
  `{:reference_picker, path, {:select, ref_path_or_inline_map}}` /
  `{:reference_picker, path, :use_inline}` to the parent LiveView (always
  `self()`, since a `LiveComponent` always runs in its parent's process),
  which is expected to `handle_info/2` those and update `@data` itself the
  same "the LiveView owns `@data`" model every other field in
  `MaestroWeb.WorkspaceLive.Form` already follows, just relayed through a
  message instead of a direct `phx-*` event since this is a component, not
  the LiveView itself.
  """

  use MaestroWeb, :live_component

  alias Maestro.Resources

  @max_results 50

  @impl true
  def update(%{id: id, workspace: workspace, kind: kind, path: path, value: value}, socket) do
    {:ok,
     socket
     |> assign(:id, id)
     |> assign(:workspace, workspace)
     |> assign(:kind, kind)
     |> assign(:path, path)
     |> assign(:value, value)
     |> assign_new(:entries, fn -> [] end)
     |> assign_new(:inline_raw, fn -> inline_raw(value) end)
     |> assign_new(:inline_error, fn -> nil end)
     |> assign_new(:query, fn -> "" end)
     |> assign_new(:open, fn -> false end)}
  end

  defp inline_raw(value) when is_map(value), do: Jason.encode!(value, pretty: true)
  defp inline_raw(_value), do: "{}"

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    entries = load_entries(socket.assigns.workspace, socket.assigns.kind, query)

    {:noreply,
     socket |> assign(:query, query) |> assign(:entries, entries) |> assign(:open, true)}
  end

  def handle_event("open", _params, socket) do
    entries = load_entries(socket.assigns.workspace, socket.assigns.kind, socket.assigns.query)
    {:noreply, socket |> assign(:entries, entries) |> assign(:open, true)}
  end

  def handle_event("select", %{"entry_path" => entry_path}, socket) do
    send(self(), {:reference_picker, socket.assigns.path, {:select, entry_path}})
    {:noreply, assign(socket, :open, false)}
  end

  def handle_event("clear", _params, socket) do
    entries = load_entries(socket.assigns.workspace, socket.assigns.kind, socket.assigns.query)
    {:noreply, socket |> assign(:entries, entries) |> assign(:open, true)}
  end

  def handle_event("use-inline", _params, socket) do
    send(self(), {:reference_picker, socket.assigns.path, :use_inline})
    {:noreply, assign(socket, :open, false)}
  end

  def handle_event("clear-value", _params, socket) do
    send(self(), {:reference_picker, socket.assigns.path, :clear})
    {:noreply, assign(socket, :open, false)}
  end

  def handle_event("update-inline", %{"value" => raw}, socket) do
    case Jason.decode(raw) do
      {:ok, value} when is_map(value) ->
        send(self(), {:reference_picker, socket.assigns.path, {:select, value}})
        {:noreply, socket |> assign(:inline_raw, raw) |> assign(:inline_error, nil)}

      {:ok, _not_an_object} ->
        {:noreply, assign(socket, :inline_error, "Must be a JSON object.")}

      {:error, _reason} ->
        {:noreply, socket |> assign(:inline_raw, raw) |> assign(:inline_error, "Invalid JSON.")}
    end
  end

  defp load_entries(workspace, kind, query) do
    workspace
    |> Resources.list_paths(kind)
    |> filter_paths(query)
    |> Enum.take(@max_results + 1)
    |> Enum.flat_map(fn path ->
      case Resources.fetch(workspace, kind, path) do
        {:ok, data} -> [%{path: path, name: data["name"]}]
        {:error, _reason} -> []
      end
    end)
  end

  defp filter_paths(paths, ""), do: paths

  defp filter_paths(paths, query) do
    query = String.downcase(query)
    Enum.filter(paths, &String.contains?(String.downcase(&1), query))
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        truncated?: length(assigns.entries) > @max_results,
        entries: Enum.take(assigns.entries, @max_results),
        max_results: @max_results
      )

    ~H"""
    <div id={@id} class="relative">
      <div :if={is_binary(@value)} class="flex items-center gap-2">
        <span class="font-mono text-sm bg-base-200 rounded px-2 py-1">{@value}</span>
        <.button phx-click="clear" phx-target={@myself}>Change</.button>
      </div>

      <div :if={is_map(@value)}>
        <div class="flex items-center gap-2 mb-1">
          <span class="badge badge-soft badge-sm">inline</span>
          <.button phx-click="open" phx-target={@myself}>Use existing instead</.button>
        </div>
        <textarea
          phx-change="update-inline"
          phx-target={@myself}
          name="value"
          class={["w-full textarea font-mono", @inline_error && "textarea-error"]}
          rows="4"
        >{@inline_raw}</textarea>
        <p :if={@inline_error} class="mt-1 flex gap-2 items-center text-sm text-error">
          <.icon name="hero-exclamation-circle" class="size-4" />{@inline_error}
        </p>
      </div>

      <div :if={@open}>
        <input
          type="text"
          value={@query}
          phx-change="search"
          phx-target={@myself}
          phx-debounce="150"
          name="query"
          placeholder={"Search #{@kind}s by path or name..."}
          class="input input-sm w-full mt-1"
        />

        <ul class="menu bg-base-100 border border-base-300 rounded-box mt-1 max-h-48 overflow-y-auto flex-nowrap">
          <li :for={entry <- @entries}>
            <a phx-click="select" phx-value-entry_path={entry.path} phx-target={@myself}>
              <span class="font-mono text-sm">{entry.path}</span>
              <span :if={entry.name} class="text-xs text-base-content/70">{entry.name}</span>
            </a>
          </li>
          <li :if={@entries == []}>
            <span class="text-sm text-base-content/70">No {@kind}s found.</span>
          </li>
          <li :if={@truncated?}>
            <span class="text-xs text-base-content/50">
              Showing first {@max_results} results.
            </span>
          </li>
        </ul>

        <div class="flex gap-2 mt-1">
          <.button phx-click="use-inline" phx-target={@myself}>
            Define inline instead
          </.button>
          <.button :if={@value != ""} phx-click="clear-value" phx-target={@myself}>
            Clear
          </.button>
        </div>
      </div>
    </div>
    """
  end
end
