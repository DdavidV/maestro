defmodule Maestro.Resources.Resolver do
  @moduledoc """
  Resolves test suites into executable test definitions.

  The resolver expands resource references (`suite`, `scenario`, `template`,
  and `dataset`) into their concrete values and recursively resolves nested
  scenario steps, merging each step's dataset with what it inherited from
  its caller.

  A resolved dataset is always a *dataset body* `%{"data" => map}` for a
  single bag of values, or `%{"rows" => [map, ...]}` for a table to iterate over.

  A `scenario` or `template` reference may be a string file path, or a
  literal inline body.
  The two forms resolve to the same shape either way, so nothing downstream needs to
  know which one an author used.
  Inline scenarios can't participate in cycle detection (they have no name to revisit)
  but still count toward `max_scenario_depth/0`.

  ## Atom-keyed output

  A successfully resolved suite (`t:Maestro.suite/0`) is atom-keyed at every
  structural level suite/testcase/step/template/scenario/dataset-envelope/
  save-entry field names are all fixed by the JSON schemas, so they become
  atoms, which lets `t:Maestro.step/0` and friends be precise, Dialyzer-
  checkable types instead of a catch-all `%{String.t() => term()}`.
  Anything with an *open*, author-defined vocabulary stays string-keyed:
  dataset `data`/`rows`  contents, a template's `payload`/`options` bodies,
  and `save` state all  keep whatever field names the suite author chose
  there's no fixed set to atomize, and blindly atomizing arbitrary/unbounded strings
  would leak atoms for the lifetime of the VM. This conversion happens once, in a single pass
  over the fully-resolved tree (`atomize_suite/1` below) resolution itself
  still works in plain string-keyed maps throughout, matching the raw JSON
  input and `Maestro.Resources.Schemas` validation.

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

  @spec resolve(String.t() | map) :: {:ok, Maestro.suite()} | {:error, resolve_error | term}
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
    with :ok <- check_unique_testcase_ids(testcases),
         {:ok, testcases} <- resolve_testcases(testcases) do
      {:ok, atomize_suite(Map.put(suite, "testcases", testcases))}
    end
  end

  # Testcase ids must be unique within a suite so status/result reporting can
  # key by id unambiguously.
  defp check_unique_testcase_ids(testcases) do
    testcases
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {%{"id" => id}, index}, seen ->
      Map.update(seen, id, [index], &[index | &1])
    end)
    |> Enum.find(fn {_id, indexes} -> length(indexes) > 1 end)
    |> case do
      nil ->
        :ok

      {id, indexes} ->
        {:error, {:duplicate_testcase_id, id, Enum.sort(indexes)}}
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

  def resolve_steps(steps, inherited_dataset \\ nil, scope \\ new_scope()) do
    steps
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {step, index}, {:ok, acc} ->
      case resolve_step(step, inherited_dataset, scope) do
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

  # `scope` tracks recursion state across nested scenario calls:
  # `visited` is the list of *named* scenario paths currently on the call
  # stack (used for cycle detection, an inline scenario body has no name to
  # revisit, so it can't participate in a cycle by definition, named or not).
  # `depth` counts every scenario call, named or inline, against
  # `max_scenario_depth/0` as a backstop against pathological nesting
  # regardless of whether it's built from files or inline bodies.
  @doc false
  def new_scope, do: %{visited: [], depth: 0}

  defp resolve_step(%{"template" => template} = step, inherited_dataset, _scope) do
    with {:ok, template} <- resolve_template(template),
         {:ok, dataset} <- resolve_dataset(Map.get(step, "dataset")),
         {:ok, merged_dataset} <- fold_datasets([inherited_dataset, dataset]) do
      {:ok,
       step
       |> Map.put("template", template)
       |> Map.put("dataset", merged_dataset)}
    end
  end

  defp resolve_step(%{"scenario" => scenario_ref} = step, inherited_dataset, scope) do
    %{visited: visited, depth: depth} = scope

    cond do
      is_binary(scenario_ref) and scenario_ref in visited ->
        error = {:cycle_detected, scenario_ref, Enum.reverse([scenario_ref | visited])}
        with_path({:error, error}, ref_segment(:scenario, scenario_ref))

      depth >= max_scenario_depth() ->
        error = {:max_depth_exceeded, max_scenario_depth()}
        maybe_with_ref_path({:error, error}, :scenario, scenario_ref)

      true ->
        with {:ok, scenario} <- resolve_scenario(scenario_ref),
             {:ok, default_dataset} <- resolve_dataset(Map.get(scenario, "default_dataset")),
             {:ok, dataset} <- resolve_dataset(Map.get(step, "dataset")),
             {:ok, merged_dataset} <-
               fold_datasets([inherited_dataset, default_dataset, dataset]) do
          next_visited = if is_binary(scenario_ref), do: [scenario_ref | visited], else: visited
          next_scope = %{visited: next_visited, depth: depth + 1}

          with {:ok, steps} <- resolve_steps(scenario["steps"], merged_dataset, next_scope) do
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

  defp resolve_template(%{} = template), do: {:ok, template}

  defp resolve_template(template) when is_binary(template) do
    with_path(Resources.fetch(:template, template), ref_segment(:template, template))
  end

  defp resolve_scenario(%{} = scenario), do: {:ok, scenario}

  defp resolve_scenario(scenario) when is_binary(scenario) do
    with_path(Resources.fetch(:scenario, scenario), ref_segment(:scenario, scenario))
  end

  defp resolve_dataset(nil), do: {:ok, nil}
  defp resolve_dataset(%{} = dataset), do: {:ok, dataset}

  defp resolve_dataset(dataset) when is_binary(dataset) do
    with_path(Resources.fetch(:dataset, dataset), ref_segment(:dataset, dataset))
  end

  defp maybe_with_ref_path(error, kind, name) when is_binary(name),
    do: with_path(error, ref_segment(kind, name))

  defp maybe_with_ref_path(error, _kind, _name), do: error

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

  # One final pass over the fully-resolved (string-keyed) tree, converting
  # every *structural* key to an atom.
  defp atomize_suite(suite) do
    suite
    |> pick([:id, :name, :description, :tags])
    |> Map.put(:testcases, Enum.map(suite["testcases"], &atomize_testcase/1))
  end

  defp atomize_testcase(testcase) do
    testcase
    |> pick([:id, :name, :description])
    |> Map.put(:steps, Enum.map(testcase["steps"], &atomize_step/1))
  end

  defp atomize_step(%{"scenario" => scenario} = step) do
    step
    |> pick([:name])
    |> Map.put(:scenario, atomize_scenario(scenario))
    |> Map.put(:dataset, atomize_dataset(step["dataset"]))
  end

  defp atomize_step(%{"template" => template} = step) do
    step
    |> pick([:name, :client])
    |> Map.put(:template, atomize_template(template))
    |> Map.put(:dataset, atomize_dataset(step["dataset"]))
    |> put_assert(step)
    |> put_save(step)
  end

  defp put_save(atomized_step, %{"save" => save}) do
    Map.put(atomized_step, :save, Enum.map(save, &pick(&1, [:path, :as])))
  end

  defp put_save(atomized_step, _step), do: atomized_step

  defp put_assert(atomized_step, %{"assert" => assert}) do
    Map.put(atomized_step, :assert, Enum.map(assert, &atomize_assertion/1))
  end

  defp put_assert(atomized_step, _step), do: atomized_step

  # An assertion entry is flat, not wrapped in an opaque properties bag:
  # `matcher`/`path`/`expected` are the fixed common envelope (atomized),
  # but a matcher may attach further matcher-specific fields beyond those
  # three (open vocabulary, same principle as a dataset's field names)
  # those are merged back in string-keyed rather than dropped.
  @assertion_keys [:matcher, :path, :expected]

  defp atomize_assertion(assertion) do
    assertion
    |> pick(@assertion_keys)
    |> Map.merge(Map.drop(assertion, Enum.map(@assertion_keys, &Atom.to_string/1)))
    |> Map.put_new(:matcher, "json_match")
  end

  defp atomize_template(template) do
    template
    |> pick([:name, :description, :clients, :payload])
    |> Map.put(:options, Map.get(template, "options", %{}))
  end

  defp atomize_scenario(scenario) do
    scenario
    |> pick([:name, :description])
    |> Map.put(:default_dataset, atomize_dataset(scenario["default_dataset"]))
    |> Map.put(:steps, Enum.map(scenario["steps"], &atomize_step/1))
  end

  defp atomize_dataset(nil), do: nil
  defp atomize_dataset(dataset), do: pick(dataset, [:data, :rows])

  # Builds a new map with `keys` (atoms) as keys, pulling each value from
  # `map`'s matching string key. Keys absent from `map` are simply omitted
  # (this is how optional structural fields, e.g. a step's `name`, stay
  # absent rather than becoming `nil` entries) values themselves are
  # carried over unchanged, so open-vocabulary content nested underneath
  # (dataset fields, payload/options bodies) is untouched.
  defp pick(map, keys) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case Map.fetch(map, Atom.to_string(key)) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end
end
