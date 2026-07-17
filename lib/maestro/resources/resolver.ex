defmodule Maestro.Resources.Resolver do
  @moduledoc """
  Resolves test suites into executable test definitions.

  The resolver expands resource references (`suite`, `scenario`, `template`,
  and `dataset`) into their concrete values and recursively resolves nested
  scenario steps, merging each step's dataset with what it inherited from
  its caller.

  A resolved dataset is always a *dataset body* `%{"data" => map}` for a
  single bag of values, or `%{"rows" => [map, ...]}` for a table to iterate over.
  """

  alias Maestro.Resources.Schemas
  alias Maestro.Resources

  @type dataset_body :: %{String.t() => map} | nil

  @default_max_scenario_depth 50

  def resolve(suite_reference) when is_binary(suite_reference) do
    # Resources.fetch/2 already validates against the suite schema, so go
    # straight to expanding testcases instead of routing back through
    # resolve/1's map clause, which would validate a second time.
    with {:ok, suite} <- Resources.fetch(:suite, suite_reference) do
      expand(suite)
    end
  end

  def resolve(suite) when is_map(suite) do
    with :ok <- Schemas.validate(:suite, suite) do
      expand(suite)
    end
  end

  defp expand(%{"testcases" => testcases} = suite) do
    with {:ok, testcases} <- resolve_testcases(testcases) do
      {:ok, Map.put(suite, "testcases", testcases)}
    end
  end

  defp resolve_testcases(testcases) do
    Enum.reduce_while(testcases, {:ok, []}, fn testcase, {:ok, acc} ->
      case resolve_testcase(testcase) do
        {:ok, testcase} ->
          {:cont, {:ok, [testcase | acc]}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, testcases} ->
        {:ok, Enum.reverse(testcases)}

      error ->
        error
    end
  end

  defp resolve_testcase(%{"steps" => steps} = testcase) do
    with {:ok, steps} <- resolve_steps(steps) do
      {:ok, Map.put(testcase, "steps", steps)}
    end
  end

  def resolve_steps(steps, inherited_dataset \\ nil, visited \\ []) do
    Enum.reduce_while(steps, {:ok, []}, fn step, {:ok, acc} ->
      case resolve_step(step, inherited_dataset, visited) do
        {:ok, resolved_step} ->
          {:cont, {:ok, [resolved_step | acc]}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, steps} ->
        {:ok, Enum.reverse(steps)}

      error ->
        error
    end
  end

  defp resolve_step(%{"template" => template_name} = step, inherited_dataset, _visited) do
    with {:ok, template} <- Resources.fetch(:template, template_name),
         {:ok, dataset} <- resolve_dataset(Map.get(step, "dataset")),
         {:ok, merged_dataset} <- fold_datasets([inherited_dataset, dataset]) do
      {:ok,
       step
       |> Map.put("template", template)
       |> Map.put("dataset", merged_dataset)}
    end
  end

  defp resolve_step(%{"scenario" => scenario_name} = step, inherited_dataset, visited) do
    cond do
      scenario_name in visited ->
        {:error, {:cycle_detected, scenario_name, Enum.reverse([scenario_name | visited])}}

      length(visited) >= max_scenario_depth() ->
        {:error, {:max_depth_exceeded, max_scenario_depth()}}

      true ->
        with {:ok, scenario} <- Resources.fetch(:scenario, scenario_name),
             {:ok, default_dataset} <- resolve_dataset(Map.get(scenario, "default_dataset")),
             {:ok, dataset} <- resolve_dataset(Map.get(step, "dataset")),
             {:ok, merged_dataset} <-
               fold_datasets([inherited_dataset, default_dataset, dataset]) do
          with {:ok, steps} <-
                 resolve_steps(scenario["steps"], merged_dataset, [scenario_name | visited]) do
            {:ok,
             step
             |> Map.put(
               "scenario",
               scenario
               |> Map.put("default_dataset", merged_dataset)
               |> Map.put("steps", steps)
             )
             |> Map.put("dataset", merged_dataset)}
          end
        end
    end
  end

  defp resolve_dataset(nil), do: {:ok, nil}
  defp resolve_dataset(%{} = dataset), do: {:ok, dataset}
  defp resolve_dataset(dataset) when is_binary(dataset), do: Resources.fetch(:dataset, dataset)

  @doc """
  The maximum number of nested scenario calls allowed while resolving a
  suite, as a backstop against pathological (but acyclic) scenario chains.

  Reads `config :maestro, :max_scenario_depth`, falling back to
  #{@default_max_scenario_depth} if unset.
  """
  @spec max_scenario_depth() :: pos_integer
  def max_scenario_depth do
    Application.get_env(:maestro, :max_scenario_depth, @default_max_scenario_depth)
  end

  @doc """
  Folds a list of dataset bodies (outermost/oldest first, e.g.
  `[inherited_dataset, default_dataset, dataset]`) into one merged body,
  later entries taking precedence over earlier ones. `nil` entries (absent
  dataset/default_dataset) are skipped. If every entry is `nil`, that's an
  error there's nothing to render a template or scenario step from.
  """
  @spec fold_datasets([dataset_body]) ::
          {:ok, dataset_body} | {:error, :no_dataset | :ambiguous_dataset_merge}
  def fold_datasets(bodies) do
    Enum.reduce_while(bodies, {:ok, nil}, fn next, {:ok, acc} ->
      case merge_dataset(acc, next) do
        {:ok, merged} -> {:cont, {:ok, merged}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, nil} -> {:error, :no_dataset}
      result -> result
    end
  end

  @doc """
  Merges two dataset bodies, `next` taking precedence over `previous`.

  Either side may be `nil` which means the other side passes through
  unchanged. If both sides have `"rows"`, that's an error: combining two row
  tables (cross product? zip?) has no non-surprising default, so it's
  rejected rather than guessed at (could be a later feature).
  Otherwise: if both sides are `"data"`, they shallow-merge with `next`'s fields
  winning on collision (same rule as before, now applied inside the envelope).
  If exactly one side has `"rows"`, the other side's `"data"` (if any) is shallow-merged into every
  row, but each row's own fields always win on collision, regardless of
  which side (`previous` or `next`) carries the rows: a row is inherently
  more specific than a broadcast default.
  """
  @spec merge_dataset(dataset_body, dataset_body) ::
          {:ok, dataset_body} | {:error, :ambiguous_dataset_merge}
  def merge_dataset(nil, nil), do: {:ok, nil}
  def merge_dataset(previous, nil), do: {:ok, previous}
  def merge_dataset(nil, next), do: {:ok, next}

  def merge_dataset(%{"rows" => _}, %{"rows" => _}), do: {:error, :ambiguous_dataset_merge}

  def merge_dataset(%{"data" => previous}, %{"data" => next}) do
    {:ok, %{"data" => Map.merge(previous, next)}}
  end

  def merge_dataset(%{"rows" => rows}, %{"data" => defaults}) do
    {:ok, %{"rows" => Enum.map(rows, &Map.merge(defaults, &1))}}
  end

  def merge_dataset(%{"data" => defaults}, %{"rows" => rows}) do
    {:ok, %{"rows" => Enum.map(rows, &Map.merge(defaults, &1))}}
  end
end
