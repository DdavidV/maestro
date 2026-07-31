defmodule MaestroWeb.WorkspaceLive.Index do
  use MaestroWeb, :live_view

  alias Maestro.Workspaces

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Workspaces")
     |> assign(:form, to_form(%{"name" => "", "root_dir" => ""}))
     |> assign(:query, "")
     |> assign(:show_new_workspace, false)
     |> assign_workspaces()}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply,
     socket
     |> assign(:query, query)
     |> assign_workspaces()}
  end

  def handle_event("open-new-workspace", _params, socket) do
    {:noreply, assign(socket, :show_new_workspace, true)}
  end

  def handle_event("close-new-workspace", _params, socket) do
    {:noreply, assign(socket, :show_new_workspace, false)}
  end

  def handle_event("create", %{"name" => name, "root_dir" => root_dir}, socket) do
    case Workspaces.create(name, root_dir) do
      {:ok, workspace} ->
        {:noreply,
         socket
         |> put_flash(:info, "Workspace #{workspace.name} created.")
         |> assign(:form, to_form(%{"name" => "", "root_dir" => ""}))
         |> assign(:show_new_workspace, false)
         |> assign_workspaces()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create workspace: #{inspect(reason)}")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    :ok = Workspaces.delete(id)

    {:noreply,
     socket
     |> put_flash(:info, "Workspace closed.")
     |> assign_workspaces()}
  end

  defp assign_workspaces(socket) do
    query = String.downcase(socket.assigns.query)

    workspaces =
      Workspaces.list()
      |> Enum.filter(&String.contains?(String.downcase(&1.name), query))

    assign(socket, :workspaces, workspaces)
  end
end
