defmodule Maestro.Core.AssertRunner do
  @moduledoc """
  Runs a step's `assert` entries against its response.

  Looks each `t:Maestro.assertion/0`'s `:matcher` name up via
  `Maestro.Assert.Registry` and dispatches to it. An empty `assertions`
  list is a no-op (`{:ok, []}`) a step with no `assert` entries is
  unaffected.
  """

  alias Maestro.Assert.AssertionResult
  alias Maestro.Assert.Reason
  alias Maestro.Assert.Registry
  alias Maestro.Core.Interpolation

  @doc """
  Runs every entry in `assertions` against `actual`, returning the
  aggregate status (`:ok` only if every entry passed) alongside each
  individual result.
  """
  @spec run_assertions([Maestro.assertion()], actual :: term, Interpolation.context()) ::
          {:ok | :error, [AssertionResult.t()]}
  def run_assertions(assertions, actual, context) do
    results = Enum.map(assertions, &run_assertion(&1, actual, context))
    status = if Enum.all?(results, &(&1.status == :ok)), do: :ok, else: :error
    {status, results}
  end

  defp run_assertion(%{matcher: name} = assertion, actual, context) do
    case Registry.fetch(name) do
      {:ok, module} ->
        case module.match(assertion, actual, context) do
          :ok ->
            %AssertionResult{status: :ok, assertion: assertion, actual: actual, reasons: []}

          {:error, reasons} ->
            %AssertionResult{
              status: :error,
              assertion: assertion,
              actual: actual,
              reasons: reasons
            }
        end

      {:error, _reason} ->
        %AssertionResult{
          status: :error,
          assertion: assertion,
          actual: actual,
          reasons: [Reason.new(:matcher_not_found, name, nil)]
        }
    end
  end
end
