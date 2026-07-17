defmodule Maestro.Resources.Resolver do
  @moduledoc """
  Resolves test suites into executable test definitions.

  The resolver expands resource references (`suite`, `scenario`, `template`,
  and `dataset`) into their concrete values and recursively resolves nested
  scenario steps.
  """

  alias Maestro.Resources.Schemas
  alias Maestro.Resources

  def resolve(suite_reference) when is_binary(suite_reference) do
    case Resources.fetch(:suite, suite_reference) do
      {:ok, suite} ->
        resolve(suite);
      {:error, reason} ->
        {:error, reason}
    end
  end
  def resolve(suite) when is_map(suite) do
    # When a suite_reference is provided it gets validated 2 times...
    # oh well it is bettern than never...
    with :ok <- Schemas.validate(:suite, suite),
         %{"testcases" => testcases} = suite,
         {:ok, testcases} <- resolve_testcases(testcases) do
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

  def resolve_steps(steps, dataset \\ %{}) do
    Enum.reduce_while(steps, {:ok, []}, fn step, {:ok, acc} ->
      case resolve_step(step, dataset) do
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

  defp resolve_step(%{"template" => template_name} = step, inherited_dataset) do
    with {:ok, template} <- Resources.fetch(:template, template_name),
         {:ok, dataset} <- resolve_dataset(Map.get(step, "dataset", %{})) do
      {:ok,
       step
       |> Map.put("template", template)
       |> Map.put("dataset", Map.merge(inherited_dataset, dataset))}
    end
  end
  defp resolve_step(%{"scenario" => scenario_name} = step, inherited_dataset) do
    with {:ok, scenario} <- Resources.fetch(:scenario, scenario_name),
         default_dataset = Map.get(scenario, "default_dataset", %{}),
         {:ok, default_dataset} <- resolve_dataset(default_dataset),
         {:ok, dataset} <- resolve_dataset(Map.get(step, "dataset", %{})) do
      merged_dataset =
        inherited_dataset
        |> Map.merge(default_dataset)
        |> Map.merge(dataset)

      with {:ok, steps} <- resolve_steps(scenario["steps"], merged_dataset) do
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

  defp resolve_dataset(dataset) when is_map(dataset), do: {:ok, dataset}
  defp resolve_dataset(dataset), do: Resources.fetch(:dataset, dataset)
end
