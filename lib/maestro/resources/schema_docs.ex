defmodule Maestro.Resources.SchemaDocs do
  @moduledoc """
  Reads the raw `priv/schemas/*.schema.json` files once at boot (see
  `Maestro.Application`) and flattens every `properties.<field>.description`
  into a `{kind, field_path}` lookup, so form fields can show a tooltip
  sourced straight from the schema instead of duplicating help text by
  hand in every `.heex` form.

  Reads the *raw* JSON directly (not `Maestro.Resources.Schemas`'s
  `ExJsonSchema.Schema.resolve/1` output) `description` isn't guaranteed
  to survive schema resolution, and this module only ever needs plain
  string lookup, not compiled-schema validation structures.

  `field_path` is a list of string keys from the schema root to the field,
  e.g. `["data"]` for a dataset's top-level `data` property, mirroring how
  a caller already knows which nested field it's rendering (there's no
  need for a single dotted-string key format since callers always know
  their own path segments at the call site).
  """

  @persistent_term_key {__MODULE__, :tooltips}

  @kinds [:suite, :scenario, :dataset, :template, :test_plan]

  @doc """
  Reads and flattens every schema's `properties.*.description` into
  `:persistent_term`, keyed by `{kind, field_path}`.
  """
  @spec load! :: :ok
  def load! do
    tooltips =
      Map.new(@kinds, fn kind ->
        schema = load_schema_file(kind)
        {kind, flatten_properties(schema, schema, [])}
      end)

    :persistent_term.put(@persistent_term_key, tooltips)
    :ok
  end

  @doc """
  The `description` for `kind`'s field at `field_path` (e.g.
  `tooltip(:dataset, ["data"])`), or `nil` if the schema has none (or the
  path doesn't exist).
  """
  @spec tooltip(atom, [String.t()]) :: String.t() | nil
  def tooltip(kind, field_path) when kind in @kinds and is_list(field_path) do
    @persistent_term_key
    |> :persistent_term.get()
    |> Map.fetch!(kind)
    |> Map.get(field_path)
  end

  defp load_schema_file(kind) do
    Path.join([:code.priv_dir(:maestro), "schemas", "#{kind}.schema.json"])
    |> File.read!()
    |> Jason.decode!()
  end

  defp flatten_properties(%{"$ref" => ref}, root, path) do
    flatten_properties(resolve_ref(root, ref), root, path)
  end

  defp flatten_properties(%{"properties" => properties} = schema, root, path)
       when is_map(properties) do
    own = flatten_from(schema, path)

    Enum.reduce(properties, own, fn {key, field_schema}, acc ->
      Map.merge(acc, flatten_properties(field_schema, root, path ++ [key]))
    end)
  end

  defp flatten_properties(schema, _root, path), do: flatten_from(schema, path)

  defp flatten_from(%{"description" => description}, path) when path != [] do
    %{path => description}
  end

  defp flatten_from(_schema, _path), do: %{}

  # Resolves an in-document JSON Pointer ref (e.g. "#/$defs/body/properties/data")
  # by walking `root`. These schemas only ever `$ref` within the same file at
  # the property level (cross-file `$ref`s exist too, but only nested inside
  # `oneOf` step/dataset bodies that this tooltip lookup never needs to
  # descend into), so no cross-file resolution is needed here.
  defp resolve_ref(root, "#/" <> pointer) do
    pointer
    |> String.split("/")
    |> Enum.reduce(root, fn segment, node -> Map.fetch!(node, segment) end)
  end
end
