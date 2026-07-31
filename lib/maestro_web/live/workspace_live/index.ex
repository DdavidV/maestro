defmodule MaestroWeb.WorkspaceLive.Index do
  use MaestroWeb, :live_view

  alias Maestro.Workspaces

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Workspaces")
     |> assign(:form, to_form(%{"name" => "", "root_dir" => "", "remote_url" => ""}))
     |> assign(:query, "")
     |> assign(:show_new_workspace, false)
     |> assign(:new_workspace_mode, "local")
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
    {:noreply,
     socket
     |> assign(:show_new_workspace, true)
     |> assign(:new_workspace_mode, "local")
     |> assign(
       :form,
       to_form(%{"name" => "", "root_dir" => suggested_root_dir(), "remote_url" => ""})
     )}
  end

  def handle_event("close-new-workspace", _params, socket) do
    {:noreply, assign(socket, :show_new_workspace, false)}
  end

  def handle_event("new-workspace-mode", %{"mode" => mode}, socket) do
    root_dir = if mode == "local", do: suggested_root_dir(), else: ""

    {:noreply,
     socket
     |> assign(:new_workspace_mode, mode)
     |> assign(:form, to_form(%{"name" => "", "root_dir" => root_dir, "remote_url" => ""}))}
  end

  def handle_event("create", %{"name" => name, "root_dir" => root_dir} = params, socket) do
    result =
      case params["remote_url"] do
        remote when remote in [nil, ""] -> Workspaces.create(name, root_dir)
        remote_url -> Workspaces.create_git(name, root_dir, remote_url)
      end

    case result do
      {:ok, workspace} ->
        {:noreply,
         socket
         |> put_flash(:info, "Workspace #{workspace.name} created.")
         |> assign(:form, to_form(%{"name" => "", "root_dir" => "", "remote_url" => ""}))
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

  def handle_event("pull", %{"id" => id}, socket) do
    case Workspaces.pull(id) do
      :ok -> {:noreply, put_flash(socket, :info, "Workspace updated from its remote.")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Pull failed: #{inspect(reason)}")}
    end
  end

  defp suggested_root_dir do
    registry_dir = Workspaces.Store.registry_path() |> Path.dirname()
    Path.join([registry_dir, "workspaces", "new-workspace"])
  end

  defp assign_workspaces(socket) do
    query = String.downcase(socket.assigns.query)

    workspaces =
      Workspaces.list()
      |> Enum.filter(&String.contains?(String.downcase(&1.name), query))

    assign(socket, :workspaces, workspaces)
  end
end
