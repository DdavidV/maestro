defmodule Maestro.Workspaces.Git do
  @moduledoc """
  Thin wrapper around the `git` CLI (`System.cmd/3`)  the only place Maestro
  shells out to an external process. Maestro never manages commits, pushes,
  branches, or credentials itself: a git-backed workspace's `root_dir` is a
  plain git working tree, and the user's own git tooling (CLI, IDE, SSH
  agent, credential helper) does everything beyond clone/pull, the same
  minimal model Bruno uses for its git-backed collections.
  """

  @spec repo?(String.t()) :: boolean
  def repo?(dir), do: File.dir?(Path.join(dir, ".git"))

  @doc """
  Clones `remote_url` into `dir` if `dir` isn't already a git repo (a plain
  empty/nonexistent directory is fine  `git clone` creates it). If `dir` is
  already a git repo, this is a no-op success: re-registering a workspace
  over an already-cloned checkout must not re-clone or error.
  """
  @spec ensure_cloned(String.t(), String.t()) :: :ok | {:error, term}
  def ensure_cloned(remote_url, dir) do
    if repo?(dir) do
      :ok
    else
      run(["clone", remote_url, dir])
    end
  end

  @doc "Runs `git pull` in `dir`. `dir` must already be a git repo."
  @spec pull(String.t()) :: :ok | {:error, term}
  def pull(dir), do: run(["pull"], cd: dir)

  defp run(args, opts \\ []) do
    cmd_opts = [stderr_to_stdout: true] ++ opts

    case System.cmd("git", args, cmd_opts) do
      {_output, 0} -> :ok
      {output, _nonzero} -> {:error, {:git_failed, args, output}}
    end
  end
end
