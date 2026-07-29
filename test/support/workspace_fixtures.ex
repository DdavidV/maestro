defmodule Maestro.WorkspaceFixtures do
  @moduledoc """
  Test fixtures for the workspace-aware `Maestro.Resources`/
  `Maestro.Workspaces` API. `workspace_fixture/0` gives each test its own
  throwaway workspace (own temp `root_dir`, own temp `workspaces.json`
  registry so tests never touch the real one), automatically cleaned up via
  `on_exit` this needs `ExUnit.Callbacks.on_exit/2` to be callable, so it
  must run inside a test process, not at module load time.
  """

  alias Maestro.Resources
  alias Maestro.Workspaces.Store
  alias Maestro.Workspaces.Workspace

  @doc """
  Points `Maestro.Workspaces.Store` (the one, application-wide named
  GenServer) at a fresh, empty temp registry file for the duration of the
  calling test, restoring whatever it was pointed at before on `on_exit`,
  via `Store.reload/1`. **Tests using this must be `async: false`**: the
  `Store` is one shared process, so two tests reloading it concurrently
  would race.
  """
  @spec isolate_workspace_registry!() :: :ok
  def isolate_workspace_registry! do
    previous_path = Store.registry_path()

    temp_path =
      Path.join(
        System.tmp_dir!(),
        "maestro_workspaces_registry_#{System.unique_integer([:positive])}.json"
      )

    :ok = Store.reload(temp_path)

    ExUnit.Callbacks.on_exit(fn ->
      File.rm(temp_path)
      Store.reload(previous_path)
    end)

    :ok
  end

  @doc """
  Registers (and returns) a fresh workspace backed by its own temp
  directory, for the duration of the calling test. Calls
  `isolate_workspace_registry!/0` first if the registry hasn't already
  been isolated in this test, so this is always safe to call standalone.
  """
  @spec workspace_fixture() :: Workspace.t()
  def workspace_fixture do
    root_dir =
      Path.join(
        System.tmp_dir!(),
        "maestro_workspace_fixture_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root_dir)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(root_dir) end)

    unique = System.unique_integer([:positive])
    {:ok, workspace} = Maestro.Workspaces.create("Fixture #{unique}", root_dir)

    workspace
  end

  @doc """
  Writes `content` as the resource of `kind` at `path` within `workspace`,
  via `Maestro.Resources.write/4` (the real, schema-validating write path),
  raising if the write is rejected.
  """
  @spec resource_fixture!(Workspace.t(), Resources.kind(), String.t(), map) :: :ok
  def resource_fixture!(%Workspace{} = workspace, kind, path, content) do
    case Resources.write(workspace, kind, path, content) do
      :ok -> :ok
      {:error, reason} -> raise "resource_fixture! write failed: #{inspect(reason)}"
    end
  end

  @doc """
  Writes `content` as raw JSON (no schema validation) at `path` within
  `workspace`, bypassing `Maestro.Resources.write/4` entirely for tests
  that need a deliberately schema-invalid or malformed file already on
  disk before `fetch`/`resolve` are exercised against it (`write/4` itself
  would reject such content, since it validates before writing).
  """
  @spec raw_resource_fixture!(Workspace.t(), Resources.kind(), String.t(), map) :: :ok
  def raw_resource_fixture!(%Workspace{} = workspace, kind, path, content) do
    file = Path.join([workspace.root_dir, subdir(kind), path <> ".json"])
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, Jason.encode!(content))
    :ok
  end

  defp subdir(:suite), do: "suites"
  defp subdir(:scenario), do: "scenarios"
  defp subdir(:dataset), do: "datasets"
  defp subdir(:template), do: "templates"
  defp subdir(:test_plan), do: "test_plans"
end
