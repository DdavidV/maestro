defmodule Maestro.Resources.Schemas do
  @moduledoc """
  Loads and validates the JSON Schema documents in `priv/schemas`.

  `load!/0` is called once at application boot (see `Maestro.Application`)
  to compile the schemas and cache them in `:persistent_term`, so validation
  calls never touch disk.
  """

  @persistent_term_key {__MODULE__, :roots}

  @kinds [:suite, :scenario, :step, :dataset, :template, :test_plan]

  @type kind :: :suite | :scenario | :step | :dataset | :template | :test_plan
  @type validation_error :: {message :: String.t(), path :: String.t()}

  @doc """
  Loads and resolves every schema in `priv/schemas`, caching the result in
  `:persistent_term`.
  """
  @spec load! :: :ok
  def load! do
    roots = Map.new(@kinds, fn kind -> {kind, load_and_resolve(kind)} end)
    :persistent_term.put(@persistent_term_key, roots)
    :ok
  end

  @doc "Validates `data` against the `kind` schema."
  @spec validate(kind, map) :: :ok | {:error, [validation_error]}
  def validate(kind, data) when kind in @kinds and is_map(data) do
    root =
      @persistent_term_key
      |> :persistent_term.get()
      |> Map.fetch!(kind)

    ExJsonSchema.Validator.validate(root, data)
  end

  defp load_and_resolve(kind) do
    "#{kind}.schema.json"
    |> load_schema_file()
    |> ExJsonSchema.Schema.resolve()
  end

  @doc false
  def load_and_resolve_ref(file) do
    file
    |> Path.basename()
    |> load_schema_file()
  end

  defp load_schema_file(filename) do
    Path.join(:code.priv_dir(:maestro), "schemas")
    |> Path.join(filename)
    |> File.read!()
    |> Jason.decode!()
    |> Map.put("$schema", "http://json-schema.org/draft-07/schema#")
  end
end
