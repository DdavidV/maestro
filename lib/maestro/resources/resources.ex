defmodule Maestro.Resources do
  @moduledoc """
  Resolves suites, scenarios, datasets, and templates by file path.

  Each kind lives under its own subdirectory of `resource_dir/0`:
  ```
  <resource_dir>/suites/<path>.json
  <resource_dir>/scenarios/<path>.json
  <resource_dir>/datasets/<path>.json
  <resource_dir>/templates/<path>.json
  <resource_dir>/test_plans/<path>.json
  ```

  `<path>` is exactly the reference string used in a step/scenario/suite
  (e.g. `"checkout/seeded_users"`), extension-less, and may contain
  subdirectories for the author's own organization. There is no cache: every
  `fetch/2` call re-reads and re-validates the file, so edits, renames, and
  moves take effect immediately with no reload step.

  The directory is configurable via `config :maestro, :resource_dir, path`,
  so a host application depending on Maestro can point it at its own suites.
  Defaults to `priv/resources` under Maestro's own `priv_dir`.
  """

  alias Maestro.Resources.Schemas

  @type kind :: :suite | :scenario | :dataset | :template | :test_plan
  @type path :: String.t()
  @type reason :: :not_found | {:invalid, [Schemas.validation_error()]}

  @kinds [:suite, :scenario, :dataset, :template, :test_plan]

  @doc """
  Reads, decodes, and validates the resource of the given `kind` at `path`.

  Returns `{:error, :not_found}` if the path doesn't resolve to a readable
  file (missing, a directory, unreadable, escapes `resource_dir/0`, ...) or
  isn't valid JSON. Returns `{:error, {:invalid, reasons}}` if the file
  parses but fails the schema validation.
  """
  @spec fetch(kind, path) :: {:ok, map} | {:error, reason}
  def fetch(kind, path) when kind in @kinds and is_binary(path) do
    with {:ok, file} <- resolve_path(kind, path),
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
  The directory resources are resolved under.

  Reads `config :maestro, :resource_dir`, falling back to `priv/resources`
  under Maestro's own `priv_dir` if unset.
  """
  @spec resource_dir() :: String.t()
  def resource_dir do
    Application.get_env(:maestro, :resource_dir) ||
      Path.join(:code.priv_dir(:maestro), "resources")
  end

  defp resolve_path(kind, path) do
    root = Path.expand(resource_dir())
    file = Path.expand(Path.join([root, subdir(kind), path <> ".json"]))

    if file == root or String.starts_with?(file, root <> "/") do
      {:ok, file}
    else
      :error
    end
  end

  defp subdir(:suite), do: "suites"
  defp subdir(:scenario), do: "scenarios"
  defp subdir(:dataset), do: "datasets"
  defp subdir(:template), do: "templates"
  defp subdir(:test_plan), do: "test_plans"
end
