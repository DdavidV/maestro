defmodule Maestro.Workspaces.Store do
  @moduledoc """
  Owns `registry_path/0`'s JSON file: the list of registered workspaces.
  A `GenServer` so every read/write goes
  through one process, serializing concurrent writes (e.g. two browser
  tabs both creating a workspace at once) the same "one process owns
  writes" principle `Maestro.Core.Runner.Store` already uses for run
  results, just backed by a small file instead of an ETS table (the
  read volume here is nowhere near `Store`'s run-status-polling volume,
  so a plain `GenServer.call` for reads too is simpler and sufficient,
  no need for ETS's read-concurrency bypass).

  If `registry_path/0` doesn't exist yet at `init/1` (first boot ever), the
  registry starts out empty no workspace is auto-created; users create
  their own via `Maestro.Workspaces.create/2`.

  If `registry_path/0` exists but is malformed (invalid JSON, wrong shape,
  an unparsable field), the error is logged and the `Store` starts with an
  empty in-memory registry rather than crashing the whole application at
  boot the bad file is left untouched on disk (not overwritten) so it can
  still be inspected/recovered.
  """

  use GenServer

  require Logger

  alias Maestro.Workspaces.Git
  alias Maestro.Workspaces.Workspace

  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  The file this `Store` is *currently* persisting to  reflects the last
  `reload/1` call, if any, not just static config (unlike
  `configured_registry_path/0`, which always re-derives from config,
  ignoring any runtime `reload/1`).
  """
  @spec registry_path() :: String.t()
  def registry_path, do: GenServer.call(__MODULE__, :registry_path)

  @doc """
  The file the workspace registry is persisted to *by default*, at boot,
  before any `reload/1` call.

  Resolved in order:

    1. `config :maestro, :workspaces_registry_path`, if set: used as-is.
    2. `Path.join(Maestro.Util.host_priv_dir(), "workspaces.json")`
       otherwise: the named host app's `priv_dir` if
       `config :maestro, :host_app` is set, or Maestro's own `priv_dir`
       if not.
  """
  @spec configured_registry_path() :: String.t()
  def configured_registry_path do
    Application.get_env(:maestro, :workspaces_registry_path) ||
      Path.join(Maestro.Util.host_priv_dir(), "workspaces.json")
  end

  @spec list() :: [Workspace.t()]
  def list, do: GenServer.call(__MODULE__, :list)

  @spec get(String.t()) :: {:ok, Workspace.t()} | {:error, :not_found}
  def get(id), do: GenServer.call(__MODULE__, {:get, id})

  @spec create(String.t(), String.t()) :: {:ok, Workspace.t()} | {:error, term}
  def create(name, root_dir), do: GenServer.call(__MODULE__, {:create, name, root_dir})

  @doc """
  Registers a new git-backed workspace named `name`: clones `remote_url`
  into `root_dir` if it isn't already a git repo there (an existing checkout
  at `root_dir` is used as-is, never re-cloned).
  """
  @spec create_git(String.t(), String.t(), String.t()) :: {:ok, Workspace.t()} | {:error, term}
  def create_git(name, root_dir, remote_url) do
    GenServer.call(__MODULE__, {:create_git, name, root_dir, remote_url}, 30_000)
  end

  @doc """
  Runs `git pull` in a `vcs: :git` workspace's `root_dir`, refreshing it from
  its remote. `{:error, :not_git}` for a `vcs: :none` workspace.
  """
  @spec pull(String.t()) :: :ok | {:error, term}
  def pull(id), do: GenServer.call(__MODULE__, {:pull, id}, 30_000)

  @spec delete(String.t()) :: :ok | {:error, :not_found}
  def delete(id), do: GenServer.call(__MODULE__, {:delete, id})

  @doc """
  Re-points this `Store` at `path` and reloads (or bootstraps) its state
  from it, discarding whatever was previously in memory. Test-only escape
  hatch: `Maestro.WorkspaceFixtures.workspace_fixture/0` calls this with a
  fresh temp file per test, since this `Store` is one named, application-wide
  GenServer (not one per test).
  """
  @spec reload(String.t()) :: :ok
  def reload(path) do
    GenServer.call(__MODULE__, {:reload, path})
  end

  @impl true
  def init(:ok) do
    state = load_or_bootstrap(configured_registry_path())
    {:ok, state}
  end

  @impl true
  def handle_call(:registry_path, _from, state) do
    {:reply, state.registry_path, state}
  end

  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.workspaces), state}
  end

  def handle_call({:get, id}, _from, state) do
    case Map.fetch(state.workspaces, id) do
      {:ok, workspace} -> {:reply, {:ok, workspace}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:create, name, root_dir}, _from, state) do
    case build_workspace(name, root_dir, Map.keys(state.workspaces)) do
      {:ok, workspace} ->
        new_state = %{state | workspaces: Map.put(state.workspaces, workspace.id, workspace)}
        :ok = persist(new_state)
        {:reply, {:ok, workspace}, new_state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:create_git, name, root_dir, remote_url}, _from, state) do
    case build_git_workspace(name, root_dir, remote_url, Map.keys(state.workspaces)) do
      {:ok, workspace} ->
        new_state = %{state | workspaces: Map.put(state.workspaces, workspace.id, workspace)}
        :ok = persist(new_state)
        {:reply, {:ok, workspace}, new_state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:pull, id}, _from, state) do
    case Map.fetch(state.workspaces, id) do
      {:ok, %Workspace{vcs: :git} = workspace} ->
        {:reply, Git.pull(workspace.root_dir), state}

      {:ok, %Workspace{vcs: :none}} ->
        {:reply, {:error, :not_git}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:delete, id}, _from, state) do
    if Map.has_key?(state.workspaces, id) do
      new_state = %{state | workspaces: Map.delete(state.workspaces, id)}
      :ok = persist(new_state)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:reload, path}, _from, _state) do
    {:reply, :ok, load_or_bootstrap(path)}
  end

  defp load_or_bootstrap(path) do
    case File.read(path) do
      {:ok, contents} -> decode(path, contents)
      {:error, :enoent} -> empty_state(path)
    end
  end

  defp empty_state(path) do
    state = %{registry_path: path, workspaces: %{}}
    :ok = persist(state)
    state
  end

  defp decode(path, contents) do
    %{registry_path: path, workspaces: decode_workspaces!(path, contents)}
  rescue
    error ->
      Logger.error(
        "Maestro.Workspaces.Store: #{path} is malformed (#{Exception.message(error)}), " <>
          "starting with an empty registry. The file is left untouched on disk."
      )

      %{registry_path: path, workspaces: %{}}
  end

  defp decode_workspaces!(registry_path, contents) do
    %{"workspaces" => workspaces} = Jason.decode!(contents)
    registry_dir = Path.dirname(registry_path)

    Map.new(workspaces, fn entry ->
      workspace = %Workspace{
        id: Map.fetch!(entry, "id"),
        name: Map.fetch!(entry, "name"),
        root_dir: absolute_root_dir(Map.fetch!(entry, "root_dir"), registry_dir),
        created_at: DateTime.from_iso8601(entry["created_at"]) |> elem(1),
        vcs: String.to_existing_atom(entry["vcs"] || "none"),
        remote_url: entry["remote_url"]
      }

      {workspace.id, workspace}
    end)
  end

  # A stored root_dir is either absolute (a workspace deliberately kept
  # outside the registry's own directory tree, e.g. a shared/mounted test
  # environment used exactly as written) or relative (see encode_workspace/2
  # below), resolved against the registry file's own directory so a registry
  # moved/deployed alongside its workspace directories together still
  # resolves correctly on a new machine or release install path.
  defp absolute_root_dir(root_dir, registry_dir) do
    case Path.type(root_dir) do
      :absolute -> root_dir
      _relative -> Path.expand(root_dir, registry_dir)
    end
  end

  defp persist(state) do
    payload = %{
      workspaces:
        Enum.map(Map.values(state.workspaces), &encode_workspace(&1, state.registry_path))
    }

    File.mkdir_p!(Path.dirname(state.registry_path))
    File.write!(state.registry_path, Jason.encode!(payload, pretty: true))
    :ok
  end

  defp encode_workspace(%Workspace{} = workspace, registry_path) do
    %{
      id: workspace.id,
      name: workspace.name,
      # Stored relative to the registry file's own directory whenever
      # root_dir lives under it (the common case: a workspace created under
      # the same priv_dir the registry itself lives in), so the registry
      # file and its workspace directories can be copied/deployed together
      # as one portable unit, without every root_dir baking in a
      # machine-specific absolute path. A root_dir that lives genuinely
      # elsewhere (a shared/mounted location outside the registry's own
      # directory tree) is stored absolute, unchanged -- Path.relative_to/2
      # (no `force:`) already returns it as-is in that case.
      root_dir: Path.relative_to(workspace.root_dir, Path.dirname(registry_path)),
      created_at: DateTime.to_iso8601(workspace.created_at),
      vcs: Atom.to_string(workspace.vcs),
      remote_url: workspace.remote_url
    }
  end

  defp build_workspace(name, root_dir, existing_ids) do
    with {:ok, root_dir} <- validate_root_dir(root_dir) do
      id = unique_slug(name, existing_ids)

      workspace = %Workspace{
        id: id,
        name: name,
        root_dir: root_dir,
        created_at: DateTime.utc_now()
      }

      {:ok, workspace}
    end
  end

  defp build_git_workspace(name, root_dir, remote_url, existing_ids) do
    with {:ok, root_dir} <- validate_absolute(root_dir),
         :ok <- Git.ensure_cloned(remote_url, root_dir) do
      ensure_subdirs!(root_dir)
      id = unique_slug(name, existing_ids)

      workspace = %Workspace{
        id: id,
        name: name,
        root_dir: root_dir,
        created_at: DateTime.utc_now(),
        vcs: :git,
        remote_url: remote_url
      }

      {:ok, workspace}
    end
  end

  defp validate_absolute(root_dir) do
    if Path.type(root_dir) != :absolute do
      {:error, {:invalid_root_dir, :not_absolute}}
    else
      {:ok, Path.expand(root_dir)}
    end
  end

  defp validate_root_dir(root_dir) do
    with {:ok, root_dir} <- validate_absolute(root_dir),
         :ok <- File.mkdir_p(root_dir) do
      ensure_subdirs!(root_dir)
      {:ok, root_dir}
    else
      {:error, {:invalid_root_dir, _reason}} = error -> error
      {:error, reason} -> {:error, {:invalid_root_dir, reason}}
    end
  end

  defp ensure_subdirs!(root_dir) do
    Enum.each(~w(suites scenarios datasets templates test_plans), fn subdir ->
      File.mkdir_p!(Path.join(root_dir, subdir))
    end)
  end

  defp unique_slug(name, existing_ids) do
    base =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    base = if base == "", do: "workspace", else: base
    dedupe(base, existing_ids, nil)
  end

  defp dedupe(base, existing_ids, nil) do
    if base in existing_ids, do: dedupe(base, existing_ids, 2), else: base
  end

  defp dedupe(base, existing_ids, n) do
    candidate = "#{base}-#{n}"
    if candidate in existing_ids, do: dedupe(base, existing_ids, n + 1), else: candidate
  end
end
