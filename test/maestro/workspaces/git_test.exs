defmodule Maestro.Workspaces.GitTest do
  use ExUnit.Case, async: true

  alias Maestro.Workspaces.Git

  setup do
    remote_dir =
      Path.join(System.tmp_dir!(), "gittest_remote_#{System.unique_integer([:positive])}")

    File.mkdir_p!(remote_dir)
    {_, 0} = System.cmd("git", ["init"], cd: remote_dir, stderr_to_stdout: true)
    {_, 0} = System.cmd("git", ["config", "user.email", "test@example.com"], cd: remote_dir)
    {_, 0} = System.cmd("git", ["config", "user.name", "Test"], cd: remote_dir)
    File.write!(Path.join(remote_dir, "README.md"), "hello")
    {_, 0} = System.cmd("git", ["add", "."], cd: remote_dir)

    {_, 0} =
      System.cmd("git", ["commit", "-m", "initial"], cd: remote_dir, stderr_to_stdout: true)

    on_exit(fn -> File.rm_rf!(remote_dir) end)

    %{remote_dir: remote_dir}
  end

  describe "repo?/1" do
    test "false for a plain directory" do
      dir = Path.join(System.tmp_dir!(), "gittest_plain_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      refute Git.repo?(dir)
    end

    test "true for a directory with a .git subdirectory", %{remote_dir: remote_dir} do
      assert Git.repo?(remote_dir)
    end
  end

  describe "ensure_cloned/2" do
    test "clones a fresh directory from a local remote", %{remote_dir: remote_dir} do
      dir = Path.join(System.tmp_dir!(), "gittest_clone_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(dir) end)

      assert :ok = Git.ensure_cloned(remote_dir, dir)
      assert Git.repo?(dir)
      assert File.read!(Path.join(dir, "README.md")) == "hello"
    end

    test "is a no-op if dir is already a git repo", %{remote_dir: remote_dir} do
      dir = Path.join(System.tmp_dir!(), "gittest_noop_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(dir) end)

      assert :ok = Git.ensure_cloned(remote_dir, dir)
      File.write!(Path.join(dir, "untracked.txt"), "kept")

      assert :ok = Git.ensure_cloned("this is not even a valid remote", dir)
      assert File.read!(Path.join(dir, "untracked.txt")) == "kept"
    end

    test "returns an error tuple for a bad remote" do
      dir = Path.join(System.tmp_dir!(), "gittest_bad_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(dir) end)

      assert {:error, {:git_failed, ["clone" | _], _output}} =
               Git.ensure_cloned("/no/such/remote/path", dir)
    end
  end

  describe "pull/1" do
    test "pulls new commits from the remote", %{remote_dir: remote_dir} do
      dir = Path.join(System.tmp_dir!(), "gittest_pull_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(dir) end)

      :ok = Git.ensure_cloned(remote_dir, dir)

      File.write!(Path.join(remote_dir, "second.md"), "more")
      {_, 0} = System.cmd("git", ["add", "."], cd: remote_dir)

      {_, 0} =
        System.cmd("git", ["commit", "-m", "second"], cd: remote_dir, stderr_to_stdout: true)

      assert :ok = Git.pull(dir)
      assert File.exists?(Path.join(dir, "second.md"))
    end

    test "returns an error tuple when dir is not a git repo" do
      dir = Path.join(System.tmp_dir!(), "gittest_notrepo_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      assert {:error, {:git_failed, ["pull"], _output}} = Git.pull(dir)
    end
  end
end
