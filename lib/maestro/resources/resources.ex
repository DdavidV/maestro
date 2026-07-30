defmodule Maestro.Resources do
  @moduledoc """
  Reads, lists, writes, and deletes suites, scenarios, datasets,
  templates, and test plans, each scoped to a `Maestro.Workspaces.Workspace`.

  Each kind lives under its own subdirectory of the workspace's `root_dir`:
  ```
  <root_dir>/suites/<path>.json
  <root_dir>/scenarios/<path>.json
  <root_dir>/datasets/<path>.json
  <root_dir>/templates/<path>.json
  <root_dir>/test_plans/<path>.json
  ```

  `<path>` is exactly the reference string used in a step/scenario/suite
  (e.g. `"checkout/seeded_users"`), extension-less, and may contain
  subdirectories for the author's own organization. There is no cache: every
  call re-reads and re-validates the file(s) involved, so edits, renames,
  and moves take effect immediately with no reload step.

  Every function takes a `Workspace.t()` (not just its `id`) so this module
  has no dependency on `Maestro.Workspaces.Store` being available a pure
  function of "given this directory, do the thing,".
  This is also what makes cross-workspace references structurally
  impossible rather than merely discouraged by convention: nothing in this
  module (or `Maestro.Resources.Resolver`, which threads the same
  `Workspace.t()` through every recursive reference it expands) ever reads
  or writes outside the one workspace it was given.

  There is no workspace-less fallback: every call requires a real
  `Workspace.t()`.
  """

  alias Maestro.Resources.Schemas
  alias Maestro.Workspaces.Workspace

  @type kind :: :suite | :scenario | :dataset | :template | :test_plan
  @type path :: String.t()
  @type reason :: :not_found | {:invalid, [Schemas.validation_error()]}

  @typedoc "One entry from `list/2`: the resource's path plus its own display fields, already parsed."
  @type list_entry :: %{
          path: path,
          name: String.t() | nil,
          description: String.t() | nil,
          tags: [String.t()]
        }

  @kinds [:suite, :scenario, :dataset, :template, :test_plan]

  @doc """
  Reads, decodes, and validates the resource of the given `kind` at `path`,
  within `workspace`.

  Returns `{:error, :not_found}` if the path doesn't resolve to a readable
  file (missing, a directory, unreadable, escapes `workspace.root_dir`,
  ...) or isn't valid JSON. Returns `{:error, {:invalid, reasons}}` if the
  file parses but fails the schema validation.
  """
  @spec fetch(Workspace.t(), kind, path) :: {:ok, map} | {:error, reason}
  def fetch(%Workspace{} = workspace, kind, path) when kind in @kinds and is_binary(path) do
    with {:ok, file} <- resolve_path(workspace, kind, path),
         {:ok, raw} <- File.read(file),
         {:ok, data} <- Jason.decode(raw) do
      case Schemas.validate(kind, data) do
        :ok -> {:ok, data}
        {:error, reasons} -> {:error, {:invalid, reasons}}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Every resource of `kind` in `workspace`, recursively, with each entry's
  own `name`/`description`/`tags` already parsed out for display (a browse
  view needs these without a second fetch per row) files that fail to
  parse/validate are skipped, not raised on a stray non-JSON or malformed
  file in a resources directory shouldn't break browsing every *other*
  resource in it.
  """
  @spec list(Workspace.t(), kind) :: [list_entry]
  def list(%Workspace{} = workspace, kind) when kind in @kinds do
    workspace
    |> list_paths(kind)
    |> Enum.flat_map(fn path ->
      case fetch(workspace, kind, path) do
        {:ok, data} -> [to_list_entry(path, data)]
        {:error, _reason} -> []
      end
    end)
  end

  @doc """
  Every resource path of `kind` in `workspace`, sorted, without reading or
  parsing any file content.

  Cheap enough to call just to get a total count or a page of paths (e.g.
  for the Explorer's index) without paying `list/2`'s per-entry parse cost
  for resources that won't even be displayed on the current page.
  """
  @spec list_paths(Workspace.t(), kind) :: [path]
  def list_paths(%Workspace{} = workspace, kind) when kind in @kinds do
    base = Path.join(Path.expand(workspace.root_dir), subdir(kind))

    base
    |> list_json_files()
    |> Enum.map(&Path.relative_to(&1, base))
    |> Enum.map(&String.replace_suffix(&1, ".json", ""))
    |> Enum.sort()
  end

  @typedoc "One level of `list_dir/3`: immediate subfolder names and leaf entries, non-recursive."
  @type dir_listing :: %{folders: [String.t()], entries: [list_entry]}

  @doc """
  The immediate contents of one directory of `kind` in `workspace`, one
  level deep only (no recursion into subfolders), for lazily expanding a
  file-tree UI one directory at a time instead of loading/parsing an
  entire (possibly huge) kind up front.

  `dir` is `""` for the kind's own root, or a path prefix (e.g.
  `"checkout"`) for a subdirectory. Returns subfolder names (sorted, no
  trailing slash) alongside this level's own leaf resources as
  `list_entry`s (parsed, same shape as `list/2`'s entries) files that fail
  to parse/validate are skipped, same as `list/2`.
  """
  @spec list_dir(Workspace.t(), kind, path) :: dir_listing
  def list_dir(%Workspace{} = workspace, kind, dir) when kind in @kinds and is_binary(dir) do
    base = Path.join(Path.expand(workspace.root_dir), subdir(kind))
    full_dir = Path.expand(if dir == "", do: base, else: Path.join(base, dir))

    if (full_dir == base or String.starts_with?(full_dir, base <> "/")) and File.dir?(full_dir) do
      full_dir
      |> File.ls!()
      |> Enum.sort()
      |> Enum.reduce(%{folders: [], entries: []}, fn name, acc ->
        entry_path = Path.join(full_dir, name)

        cond do
          File.dir?(entry_path) ->
            %{acc | folders: [name | acc.folders]}

          String.ends_with?(name, ".json") ->
            rel_path = Path.join(dir, String.replace_suffix(name, ".json", ""))

            case fetch(workspace, kind, rel_path) do
              {:ok, data} -> %{acc | entries: [to_list_entry(rel_path, data) | acc.entries]}
              {:error, _reason} -> acc
            end

          true ->
            acc
        end
      end)
      |> then(fn %{folders: folders, entries: entries} ->
        %{folders: Enum.reverse(folders), entries: Enum.reverse(entries)}
      end)
    else
      %{folders: [], entries: []}
    end
  end

  @doc """
  Validates `data` against `kind`'s schema and, only if valid, writes it to
  `path` within `workspace` (creating parent subdirectories as needed).

  Never partially writes: an invalid `data` is rejected with
  `{:error, {:invalid, reasons}}` before anything touches disk, the file at
  `path` (if any already existed) is untouched.
  """
  @spec write(Workspace.t(), kind, path, map) :: :ok | {:error, reason}
  def write(%Workspace{} = workspace, kind, path, data)
      when kind in @kinds and is_binary(path) and is_map(data) do
    case Schemas.validate(kind, data) do
      :ok ->
        with {:ok, file} <- resolve_path(workspace, kind, path) do
          File.mkdir_p!(Path.dirname(file))
          File.write!(file, Jason.encode!(data, pretty: true))
          :ok
        else
          :error -> {:error, :not_found}
        end

      {:error, reasons} ->
        {:error, {:invalid, reasons}}
    end
  end

  @doc """
  Deletes the resource of `kind` at `path` within `workspace`.

  `{:error, :not_found}` covers a missing file, same as `fetch/3`.
  """
  @spec delete(Workspace.t(), kind, path) :: :ok | {:error, :not_found}
  def delete(%Workspace{} = workspace, kind, path) when kind in @kinds and is_binary(path) do
    with {:ok, file} <- resolve_path(workspace, kind, path),
         :ok <- File.rm(file) do
      :ok
    else
      _ -> {:error, :not_found}
    end
  end

  defp resolve_path(%Workspace{} = workspace, kind, path) do
    root = Path.expand(workspace.root_dir)
    file = Path.expand(Path.join([root, subdir(kind), path <> ".json"]))

    if file == root or String.starts_with?(file, root <> "/") do
      {:ok, file}
    else
      :error
    end
  end

  defp list_json_files(base) do
    if File.dir?(base) do
      base
      |> Path.join("**/*.json")
      |> Path.wildcard()
    else
      []
    end
  end

  defp to_list_entry(path, data) do
    %{
      path: path,
      name: Map.get(data, "name"),
      description: Map.get(data, "description"),
      tags: Map.get(data, "tags", [])
    }
  end

  defp subdir(:suite), do: "suites"
  defp subdir(:scenario), do: "scenarios"
  defp subdir(:dataset), do: "datasets"
  defp subdir(:template), do: "templates"
  defp subdir(:test_plan), do: "test_plans"
end
