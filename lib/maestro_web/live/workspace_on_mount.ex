defmodule MaestroWeb.WorkspaceOnMount do
  @moduledoc """
  `on_mount` hook for every LiveView nested under `/workspace/:workspace_id`.
  Looks up the workspace named by the `:workspace_id` path param and assigns
  it as `@workspace`, so every workspace-scoped LiveView can assume it's
  always present and valid rather than re-checking `Maestro.Workspaces.get/1`
  itself. Halts with a flash + redirect to `/workspaces` if the id doesn't
  resolve to a registered workspace (e.g. a stale link, a deleted workspace).
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView

  alias Maestro.Workspaces

  def on_mount(:default, %{"workspace_id" => workspace_id}, _session, socket) do
    case Workspaces.get(workspace_id) do
      {:ok, workspace} ->
        {:cont, assign(socket, :workspace, workspace)}

      {:error, :not_found} ->
        socket =
          socket
          |> put_flash(:error, "Workspace #{inspect(workspace_id)} not found.")
          |> redirect(to: "/workspaces")

        {:halt, socket}
    end
  end
end
