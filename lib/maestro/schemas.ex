defmodule Maestro.Schemas do
  @moduledoc """
  Loads and validates the JSON Schema documents in `priv/schemas`.

  `load!/0` is called once at application boot (see `Maestro.Application`)
  to compile the schemas and cache them in `:persistent_term`, so validation
  calls never touch disk.
  """

  @persistent_term_key {__MODULE__, :roots}

  @kinds [:suite, :scenario, :step, :dataset, :template]

  @type kind :: :suite | :scenario | :step | :dataset | :template
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

  @doc "Validates `data` against the suite schema."
  @spec validate_suite(map) :: :ok | {:error, [validation_error]}
  def validate_suite(data), do: validate(:suite, data)

  @doc "Validates `data` against the scenario schema."
  @spec validate_scenario(map) :: :ok | {:error, [validation_error]}
  def validate_scenario(data), do: validate(:scenario, data)

  @doc "Validates `data` against the step schema."
  @spec validate_step(map) :: :ok | {:error, [validation_error]}
  def validate_step(data), do: validate(:step, data)

  @doc "Validates `data` against the dataset schema."
  @spec validate_dataset(map) :: :ok | {:error, [validation_error]}
  def validate_dataset(data), do: validate(:dataset, data)

  @doc "Validates `data` against the template schema."
  @spec validate_template(map) :: :ok | {:error, [validation_error]}
  def validate_template(data), do: validate(:template, data)

  @spec validate(kind, map) :: :ok | {:error, [validation_error]}
  defp validate(kind, data) do
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
