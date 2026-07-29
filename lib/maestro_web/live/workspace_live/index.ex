defmodule MaestroWeb.WorkspaceLive.Index do
  use MaestroWeb, :live_view

  alias Maestro.Workspaces

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Workspaces")
     |> assign(:form, to_form(%{"name" => "", "root_dir" => ""}))
     |> assign(:workspaces, Workspaces.list())}
  end

  @impl true
  def handle_event("create", %{"name" => name, "root_dir" => root_dir}, socket) do
    case Workspaces.create(name, root_dir) do
      {:ok, workspace} ->
        {:noreply,
         socket
         |> put_flash(:info, "Workspace #{workspace.name} created.")
         |> assign(:form, to_form(%{"name" => "", "root_dir" => ""}))
         |> assign(:workspaces, Workspaces.list())}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create workspace: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    :ok = Workspaces.delete(id)

    {:noreply,
     socket
     |> put_flash(:info, "Workspace closed.")
     |> assign(:workspaces, Workspaces.list())}
  end
end
