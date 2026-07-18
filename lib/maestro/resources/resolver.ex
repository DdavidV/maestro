defmodule Maestro.Resources.Resolver do
  @moduledoc """
  Resolves test suites into executable test definitions.

  The resolver expands resource references (`suite`, `scenario`, `template`,
  and `dataset`) into their concrete values and recursively resolves nested
  scenario steps, merging each step's dataset with what it inherited from
  its caller.

  A resolved dataset is always a *dataset body* `%{"data" => map}` for a
  single bag of values, or `%{"rows" => [map, ...]}` for a table to iterate over.

  ## Errors

  Every error returned from `resolve/1` is enriched with a `path` pinpointing
  where in the suite the failure happened.

  ```elixir
  {:error, %{
    path: [
      %{testcase_index: 0, testcase_name: "Add to cart"},
      %{step_index: 1, step_name: nil},
      %{ref_kind: :scenario, ref_name: "login_and_get_token"}
    ],
    reason: :not_found
  }}
  ```

  `path` is a list of segments, outermost first. `testcase_index`/`step_index`
  are always present  `testcase_name`/ `step_name` are included alongside when
  the suite author set one, `nil` otherwise.
  The final segment identifies the specific reference that failed:
  its kind (`:scenario`, `:template`, or `:dataset`) and the name it was referenced
  by. `reason` is the original, unmodified error from `Resources.fetch/2` or the dataset-merge
  functions below.

  Resolution stops at the first error found (fail-fast) rather than
  collecting every error in the suite.
  """

  alias Maestro.Resources.Schemas
  alias Maestro.Resources

  @type dataset_body :: %{String.t() => map} | nil
  @type path_segment ::
          %{testcase_index: non_neg_integer, testcase_name: String.t() | nil}
          | %{step_index: non_neg_integer, step_name: String.t() | nil}
          | %{ref_kind: :scenario | :template | :dataset, ref_name: String.t()}
  @type resolve_error :: %{path: [path_segment], reason: term}

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
    testcases
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {testcase, index}, {:ok, acc} ->
      case resolve_testcase(testcase) do
        {:ok, testcase} ->
          {:cont, {:ok, [testcase | acc]}}

        {:error, _} = error ->
          {:halt, with_path(error, testcase_segment(testcase, index))}
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
    steps
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {step, index}, {:ok, acc} ->
      case resolve_step(step, inherited_dataset, visited) do
        {:ok, resolved_step} ->
          {:cont, {:ok, [resolved_step | acc]}}

        {:error, _} = error ->
          {:halt, with_path(error, step_segment(step, index))}
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
    with {:ok, template} <-
           with_path(Resources.fetch(:template, template_name), ref_segment(:template, template_name)),
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
        error = {:cycle_detected, scenario_name, Enum.reverse([scenario_name | visited])}
        with_path({:error, error}, ref_segment(:scenario, scenario_name))

      length(visited) >= max_scenario_depth() ->
        error = {:max_depth_exceeded, max_scenario_depth()}
        with_path({:error, error}, ref_segment(:scenario, scenario_name))

      true ->
        with {:ok, scenario} <- fetch_scenario(scenario_name),
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

  defp fetch_scenario(scenario_name) do
    with_path(Resources.fetch(:scenario, scenario_name), ref_segment(:scenario, scenario_name))
  end

  defp resolve_dataset(nil), do: {:ok, nil}
  defp resolve_dataset(%{} = dataset), do: {:ok, dataset}

  defp resolve_dataset(dataset) when is_binary(dataset) do
    with_path(Resources.fetch(:dataset, dataset), ref_segment(:dataset, dataset))
  end

  defp testcase_segment(testcase, index) do
    %{testcase_index: index, testcase_name: Map.get(testcase, "name")}
  end

  defp step_segment(step, index) do
    %{step_index: index, step_name: Map.get(step, "name")}
  end

  defp ref_segment(kind, name) do
    %{ref_kind: kind, ref_name: name}
  end

  @doc false
  # Attaches `segment` to an {:error, _} result: wraps a bare/original reason
  # into %{path: [segment], reason: reason} on first failure, or prepends
  # `segment` to an already-enriched error's path as it bubbles back up
  # through an outer recursion level. Leaves {:ok, _} untouched.
  @spec with_path({:ok, term} | {:error, term}, path_segment) ::
          {:ok, term} | {:error, resolve_error}
  def with_path({:ok, _} = ok, _segment), do: ok
  def with_path({:error, %{path: path, reason: reason}}, segment) do
    {:error, %{path: [segment | path], reason: reason}}
  end

  def with_path({:error, reason}, segment) do
    {:error, %{path: [segment], reason: reason}}
  end

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
