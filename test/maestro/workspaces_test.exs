defmodule Maestro.WorkspacesTest do
  use ExUnit.Case, async: false

  import Maestro.WorkspaceFixtures

  setup do
    :ok = isolate_workspace_registry!()
    :ok
  end

  describe "workspace_fixture/0 isolation" do
    test "operates against an isolated registry path, not the configured (real) one" do
      real_path = Maestro.Workspaces.Store.configured_registry_path()
      assert Maestro.Workspaces.Store.registry_path() != real_path

      # The real (application-boot-bootstrapped) file may already exist from
      # this test run's own app start, but its *contents* must be untouched
      # by anything this test does.
      before_contents = File.read(real_path)

      workspace = workspace_fixture()
      assert %Maestro.Workspaces.Workspace{} = workspace
      assert File.dir?(workspace.root_dir)

      assert File.read(real_path) == before_contents
    end
  end

  describe "configured_registry_path/0" do
    test "falls back to Maestro's own priv_dir when host_app is unset" do
      path = Maestro.Workspaces.Store.configured_registry_path()

      assert path == Path.join(:code.priv_dir(:maestro), "workspaces.json")
    end

    test "respects an explicitly configured path" do
      Application.put_env(:maestro, :workspaces_registry_path, "/tmp/custom_workspaces.json")
      on_exit(fn -> Application.delete_env(:maestro, :workspaces_registry_path) end)

      assert Maestro.Workspaces.Store.configured_registry_path() ==
               "/tmp/custom_workspaces.json"
    end

    test "prefers the host app's priv_dir over the per-user fallback, when host_app is set" do
      Application.put_env(:maestro, :host_app, :maestro)
      on_exit(fn -> Application.delete_env(:maestro, :host_app) end)

      path = Maestro.Workspaces.Store.configured_registry_path()

      assert path == Path.join(:code.priv_dir(:maestro), "workspaces.json")
    end

    test "an explicit workspaces_registry_path still wins over host_app" do
      Application.put_env(:maestro, :host_app, :maestro)
      Application.put_env(:maestro, :workspaces_registry_path, "/tmp/custom_workspaces.json")

      on_exit(fn ->
        Application.delete_env(:maestro, :host_app)
        Application.delete_env(:maestro, :workspaces_registry_path)
      end)

      assert Maestro.Workspaces.Store.configured_registry_path() ==
               "/tmp/custom_workspaces.json"
    end

    test "a host_app that doesn't name a loaded application raises, rather than falling back" do
      Application.put_env(:maestro, :host_app, :totally_bogus_app_name)
      on_exit(fn -> Application.delete_env(:maestro, :host_app) end)

      assert_raise RuntimeError, ~r/does not name a loaded OTP application/, fn ->
        Maestro.Workspaces.Store.configured_registry_path()
      end
    end

    test "a non-atom host_app raises" do
      Application.put_env(:maestro, :host_app, "maestro")
      on_exit(fn -> Application.delete_env(:maestro, :host_app) end)

      assert_raise RuntimeError, ~r/must be an atom/, fn ->
        Maestro.Workspaces.Store.configured_registry_path()
      end
    end
  end

  describe "create/2, list/0, get/1, delete/1" do
    test "create registers a workspace with the five subdirectories" do
      root_dir = Path.join(System.tmp_dir!(), "wtest_#{System.unique_integer([:positive])}")
      {:ok, workspace} = Maestro.Workspaces.create("My Workspace", root_dir)

      assert workspace.id == "my-workspace"
      assert workspace.root_dir == Path.expand(root_dir)

      for subdir <- ~w(suites scenarios datasets templates test_plans) do
        assert File.dir?(Path.join(root_dir, subdir))
      end

      assert {:ok, ^workspace} = Maestro.Workspaces.get(workspace.id)
      assert workspace in Maestro.Workspaces.list()

      assert :ok = Maestro.Workspaces.delete(workspace.id)
      assert Maestro.Workspaces.get(workspace.id) == {:error, :not_found}
      assert File.dir?(root_dir), "delete/1 must not remove the directory itself"
    end

    test "two workspaces with the same name get deduplicated ids" do
      root_a = Path.join(System.tmp_dir!(), "wtest_a_#{System.unique_integer([:positive])}")
      root_b = Path.join(System.tmp_dir!(), "wtest_b_#{System.unique_integer([:positive])}")

      {:ok, a} = Maestro.Workspaces.create("Same Name", root_a)
      {:ok, b} = Maestro.Workspaces.create("Same Name", root_b)

      assert a.id != b.id
    end

    test "rejects a relative root_dir" do
      assert {:error, {:invalid_root_dir, :not_absolute}} =
               Maestro.Workspaces.create("Bad", "relative/path")
    end

    test "delete/1 of an unknown id is {:error, :not_found}" do
      assert Maestro.Workspaces.delete("does-not-exist") == {:error, :not_found}
    end
  end

  describe "registry persistence across a Store reload" do
    test "a created workspace survives a reload from the same path" do
      root_dir =
        Path.join(System.tmp_dir!(), "wtest_persist_#{System.unique_integer([:positive])}")

      {:ok, workspace} = Maestro.Workspaces.create("Persisted", root_dir)

      path = Maestro.Workspaces.Store.registry_path()
      :ok = Maestro.Workspaces.Store.reload(path)

      assert {:ok, ^workspace} = Maestro.Workspaces.get(workspace.id)
    end
  end

  describe "root_dir portability (stored relative to the registry file)" do
    test "a root_dir under the registry's own directory is stored relative on disk", %{} do
      registry_path = Maestro.Workspaces.Store.registry_path()
      registry_dir = Path.dirname(registry_path)

      root_dir =
        Path.join([registry_dir, "workspaces", "portable_#{System.unique_integer([:positive])}"])

      {:ok, workspace} = Maestro.Workspaces.create("Portable", root_dir)

      stored = registry_path |> File.read!() |> Jason.decode!()
      [entry] = Enum.filter(stored["workspaces"], &(&1["id"] == workspace.id))

      refute Path.type(entry["root_dir"]) == :absolute,
             "expected root_dir under the registry's own directory to be stored relative, " <>
               "got: #{inspect(entry["root_dir"])}"
    end

    test "a root_dir outside the registry's directory tree is stored absolute, unchanged" do
      # isolate_workspace_registry!/0 puts the registry directly under
      # System.tmp_dir!/0, so a genuinely "elsewhere" root_dir needs its own
      # isolated registry too, one level deeper, to guarantee it's not
      # accidentally nested under the other.
      registry_dir =
        Path.join(System.tmp_dir!(), "wtest_registry_dir_#{System.unique_integer([:positive])}")

      elsewhere_dir =
        Path.join(System.tmp_dir!(), "wtest_elsewhere_dir_#{System.unique_integer([:positive])}")

      on_exit(fn ->
        File.rm_rf!(registry_dir)
        File.rm_rf!(elsewhere_dir)
      end)

      registry_path = Path.join(registry_dir, "workspaces.json")
      :ok = Maestro.Workspaces.Store.reload(registry_path)

      root_dir = Path.join(elsewhere_dir, "workspace")
      {:ok, workspace} = Maestro.Workspaces.create("Elsewhere", root_dir)

      stored = registry_path |> File.read!() |> Jason.decode!()
      [entry] = Enum.filter(stored["workspaces"], &(&1["id"] == workspace.id))

      assert entry["root_dir"] == workspace.root_dir
      assert Path.type(entry["root_dir"]) == :absolute
    end

    test "surviving a copy: registry + workspace dir moved together still resolve", %{} do
      old_registry_dir =
        Path.join(System.tmp_dir!(), "wtest_move_old_#{System.unique_integer([:positive])}")

      new_registry_dir =
        Path.join(System.tmp_dir!(), "wtest_move_new_#{System.unique_integer([:positive])}")

      on_exit(fn ->
        File.rm_rf!(old_registry_dir)
        File.rm_rf!(new_registry_dir)
      end)

      File.mkdir_p!(old_registry_dir)
      old_registry_path = Path.join(old_registry_dir, "workspaces.json")
      :ok = Maestro.Workspaces.Store.reload(old_registry_path)

      root_dir = Path.join([old_registry_dir, "workspaces", "moveable"])
      {:ok, workspace} = Maestro.Workspaces.create("Moveable", root_dir)

      # Simulate deploying the registry + its workspace directories to a new
      # machine/release install path: copy the whole tree, then point a
      # fresh Store at the copy's registry file.
      File.cp_r!(old_registry_dir, new_registry_dir)
      new_registry_path = Path.join(new_registry_dir, "workspaces.json")
      :ok = Maestro.Workspaces.Store.reload(new_registry_path)

      assert {:ok, reloaded} = Maestro.Workspaces.get(workspace.id)
      assert reloaded.root_dir == Path.join([new_registry_dir, "workspaces", "moveable"])
      assert File.dir?(reloaded.root_dir)
    end
  end

  describe "a malformed registry file" do
    test "invalid JSON: Store starts empty instead of crashing, file is left untouched" do
      path =
        Path.join(System.tmp_dir!(), "wtest_malformed_#{System.unique_integer([:positive])}.json")

      File.write!(path, "{not valid json")

      assert :ok = Maestro.Workspaces.Store.reload(path)
      assert Maestro.Workspaces.list() == []
      assert File.read!(path) == "{not valid json"
    end

    test "valid JSON, wrong shape: Store starts empty instead of crashing" do
      path =
        Path.join(
          System.tmp_dir!(),
          "wtest_wrongshape_#{System.unique_integer([:positive])}.json"
        )

      File.write!(path, Jason.encode!(%{"not_workspaces" => []}))

      assert :ok = Maestro.Workspaces.Store.reload(path)
      assert Maestro.Workspaces.list() == []
    end

    test "a workspace entry missing a required field: Store starts empty instead of crashing" do
      path =
        Path.join(System.tmp_dir!(), "wtest_badentry_#{System.unique_integer([:positive])}.json")

      File.write!(path, Jason.encode!(%{"workspaces" => [%{"id" => "no-name-or-root-dir"}]}))

      assert :ok = Maestro.Workspaces.Store.reload(path)
      assert Maestro.Workspaces.list() == []
    end
  end
end
