defmodule Maestro.Workspaces do
  @moduledoc """
  Public API for registering/discovering workspaces (see
  `Maestro.Workspaces.Workspace`). Delegates straight to
  `Maestro.Workspaces.Store`, the same one-module-owns-a-concern shape
  `Maestro.Resources` already has for resource files.
  """

  alias Maestro.Workspaces.Store
  alias Maestro.Workspaces.Workspace

  @doc "Every registered workspace."
  @spec list() :: [Workspace.t()]
  def list, do: Store.list()

  @doc "Fetches the registered workspace for `id`."
  @spec get(String.t()) :: {:ok, Workspace.t()} | {:error, :not_found}
  def get(id) when is_binary(id), do: Store.get(id)

  @doc """
  Registers a new workspace named `name`, backed by `root_dir` (created,
  along with its five resource subdirectories, if it doesn't already
  exist). `root_dir` must be an absolute path.
  """
  @spec create(String.t(), String.t()) :: {:ok, Workspace.t()} | {:error, term}
  def create(name, root_dir) when is_binary(name) and is_binary(root_dir) do
    Store.create(name, root_dir)
  end

  @doc """
  Registers a new git-backed workspace named `name`: clones `remote_url`
  into `root_dir` if it isn't already a git repo there (an existing checkout
  at `root_dir` is used as-is, never re-cloned). `root_dir` must be an
  absolute path. Credentials/auth for `remote_url` are whatever the host
  machine's own `git` CLI already has configured (SSH agent, credential
  helper, stored HTTPS creds)  Maestro stores no credentials itself.
  """
  @spec create_git(String.t(), String.t(), String.t()) :: {:ok, Workspace.t()} | {:error, term}
  def create_git(name, root_dir, remote_url)
      when is_binary(name) and is_binary(root_dir) and is_binary(remote_url) do
    Store.create_git(name, root_dir, remote_url)
  end

  @doc """
  Runs `git pull` in a `vcs: :git` workspace's `root_dir`, refreshing it from
  its remote. `{:error, :not_git}` for a `vcs: :none` workspace.
  """
  @spec pull(String.t()) :: :ok | {:error, term}
  def pull(id) when is_binary(id), do: Store.pull(id)

  @doc """
  Unregisters the workspace for `id`. Never deletes `root_dir` itself
  "closing" a workspace, not "deleting my suites."
  """
  @spec delete(String.t()) :: :ok | {:error, :not_found}
  def delete(id) when is_binary(id), do: Store.delete(id)
end
