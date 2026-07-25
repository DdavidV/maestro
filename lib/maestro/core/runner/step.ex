defmodule Maestro.Core.Runner.Step do
  @moduledoc """
  Executes a fully resolved step sequence.

  ## Row iteration

  A step whose resolved dataset has `"rows"` runs once per row, right
  where it is in the sequence. Row iteration is per-step, not
  per-sequence: if two sibling steps (e.g. two nested steps of a scenario
  that was called with a rows dataset the Resolver threads the same
  merged dataset down into every nested leaf) both inherited the same
  rows-shaped dataset, each iterates independently in order:
  A-row1, A-row2, B-row1, B-row2.

  ## save state

  `save` state threads through every individual execution in strict
  sequential order, including across a single step's own row executions
  so whichever execution runs next sees whatever the immediately preceding
  one saved, regardless of whether that was a sibling step or another row
  of the same step. A step's render context is its own dataset fields
  (the whole `"data"` bag, or one row) merged with accumulated saved
  state, saved state winning on collision.

  ## Failure handling

  A step's failure (a missing interpolation key, an unregistered client, a
  client init/send error, a client crash, or a failing assertion) does not
  halt the sequence it's recorded as a failed `t:step_result/0` and
  execution continues, so a run surfaces as much diagnostic information as
  possible in one pass rather than stopping at the first problem. A
  dispatch failure (anything before a response comes back) sets
  `response` to a `Maestro.Client.Error.t()` describing what went wrong
  and where in the pipeline (interpolation, client lookup, `init/2`, or
  `send/2`, including a client module raising, which is rescued rather
  than allowed to crash the run). `save` extraction is best-effort: if a
  `save` entry's path doesn't resolve against the response, that entry is
  silently skipped rather than failing the step, a response's shape
  legitimately varies (an error body doesn't look like a success body),
  unlike a static file reference being wrong.

  ## Assertions

  Only a template-step carries `assert` a scenario call has no single
  response of its own to check, only its nested steps do, so a scenario
  call's steps are asserted individually, same as any other template-step,
  and the scenario call itself has no assertions of its own. A
  template-step's `assert` entries run once its response comes back,
  against that response and the same interpolation context (dataset fields
  merged with accumulated `save` state) the step itself rendered against.
  A failing assertion puts the step's `status` in the same `:error` bucket
  as a dispatch failure, even though the request itself succeeded
  `assertions` on `t:step_result/0` records every individual check's
  outcome regardless.
  """

  alias Maestro.Assert.AssertionResult
  alias Maestro.Client
  alias Maestro.Client.Registry, as: ClientRegistry
  alias Maestro.Core.AssertRunner
  alias Maestro.Core.Interpolation
  alias Maestro.Core.JsonPath

  @type saved :: %{String.t() => term}
  @type step_result :: %{
          name: String.t(),
          status: :ok | :error,
          client: String.t() | nil,
          rendered: Client.rendered() | nil,
          response: term | Client.Error.t(),
          assertions: [AssertionResult.t()]
        }

  @doc """
  Runs `steps` in order, threading `save` state through every execution.

  The overall return value reflects the aggregate:
  - `{:ok, {results, final_saved}}` only if every result's `status` is `:ok`
  - `{:error, {results, final_saved}}` if any step failed.
  Either way `results` and `final_saved` carry everything that happened `:error`
  here means "something failed," not "some information is missing."
  """
  @spec run_steps([Maestro.step()], saved) ::
          {:ok, {[step_result], saved}} | {:error, {[step_result], saved}}
  def run_steps(steps, saved \\ %{}) do
    {results, final_saved} =
      Enum.reduce(steps, {[], saved}, fn step, {acc, saved} ->
        {results, new_saved} = run_step(step, saved)
        {acc ++ results, new_saved}
      end)

    if Enum.all?(results, &(&1.status == :ok)) do
      {:ok, {results, final_saved}}
    else
      {:error, {results, final_saved}}
    end
  end

  defp run_step(%{scenario: scenario}, saved) do
    {_status, {results, new_saved}} = run_steps(scenario.steps, saved)
    {results, new_saved}
  end

  defp run_step(%{template: _} = step, saved) do
    case step.dataset do
      %{data: data} ->
        run_single(step, data, saved)

      %{rows: rows} ->
        Enum.reduce(rows, {[], saved}, fn row, {acc, saved} ->
          {results, new_saved} = run_single(step, row, saved)
          {acc ++ results, new_saved}
        end)
    end
  end

  defp run_single(step, row_or_data, saved) do
    context = Map.merge(row_or_data, saved)

    case dispatch(step, context) do
      {:ok, rendered, response} ->
        new_saved = extract_saves(step, response, saved)

        {status, assertion_results} =
          AssertRunner.run_assertions(Map.get(step, :assert, []), response, context)

        result = %{
          name: step_name(step),
          status: status,
          client: step.client,
          rendered: rendered,
          response: response,
          assertions: assertion_results
        }

        {[result], new_saved}

      {:error, reason} ->
        result = %{
          name: step_name(step),
          status: :error,
          client: step.client,
          rendered: nil,
          response: reason,
          assertions: []
        }

        {[result], saved}
    end
  end

  defp dispatch(step, context) do
    with {:ok, payload} <- render(step.template.payload, context, :payload_render_failed),
         {:ok, options} <- render(step.template.options, context, :options_render_failed),
         rendered = %{"payload" => payload, "options" => options},
         {:ok, entry} <- lookup(step.client),
         {:ok, response} <- client_send(entry, rendered) do
      {:ok, rendered, response}
    end
  end

  defp render(value, context, reason) do
    case Interpolation.render(value, context) do
      {:ok, rendered} -> {:ok, rendered}
      {:error, details} -> {:error, Client.Error.new(:interpolation, reason, details)}
    end
  end

  defp lookup(client_name) do
    case ClientRegistry.fetch(client_name) do
      {:ok, entry} -> {:ok, entry}
      {:error, details} -> {:error, Client.Error.new(:client_lookup, :client_not_found, details)}
    end
  end

  defp client_send(entry, rendered) do
    case Client.call(entry, rendered) do
      {:ok, response} -> {:ok, response}
      {:error, details} -> {:error, Client.Error.new(:send, :send_failed, details)}
    end
  rescue
    exception ->
      {:error, Client.Error.new(:send, :client_raised, Exception.message(exception))}
  end

  defp extract_saves(step, response, saved) do
    step
    |> Map.get(:save, [])
    |> Enum.reduce(saved, fn %{path: path, as: as}, acc ->
      case JsonPath.extract(response, path) do
        {:ok, value} -> Map.put(acc, as, value)
        {:error, _reason} -> acc
      end
    end)
  end

  defp step_name(%{name: name}) when is_binary(name), do: name
  defp step_name(%{client: client, template: template}), do: "#{client}: #{label(template)}"
  defp label(%{name: name}) when is_binary(name), do: name
  defp label(_), do: "unnamed"
end
