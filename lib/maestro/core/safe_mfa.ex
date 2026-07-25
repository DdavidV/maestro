defmodule Maestro.Core.SafeMFA do
  @moduledoc """
  Safely resolves and invokes a `{module, function, args}` triple named by
  strings from a suite file (an author-trusted escape hatch to run already-
  loaded Elixir code, the same trust level Maestro already extends to
  registered clients/matchers, not a new risk category).

  Shared by `Maestro.Matchers.JsonMatch`'s `$mfa` directive and
  `Maestro.Clients.Http`'s `transport_mfa` hook both need "call a function
  named by strings from suite JSON, safely."

  Module/function resolution never creates new atoms from suite-file
  strings (`Module.safe_concat/1` + `String.to_existing_atom/1`, never
  `Module.concat/1`/`String.to_atom/1`) an unbounded stream of suite
  files naming nonexistent modules/functions must not exhaust the atom
  table. The call itself is wrapped in `rescue`: a raise becomes a normal
  `{:error, {:mfa_raised, module, function, message}}` instead of crashing
  the run.
  """

  @type reason ::
          {:mfa_module_not_found, String.t()}
          | {:mfa_function_not_found, String.t()}
          | {:mfa_not_exported, String.t(), String.t(), arity}
          | {:mfa_raised, module, atom, String.t()}

  @doc """
  Resolves `module_str`/`function_str` and calls it with `args`, if it's
  exported with the right arity.

  On success, returns the *resolved* module/function atoms alongside the
  call's result (`{:ok, module, function, result}`), not just `result`
  callers that build their own error reason around a failing result (e.g.
  `json_match`'s `$mfa`, which reports `{:mfa_check_failed, module,
  function}`) need those atoms, not the original strings.
  """
  @spec apply(String.t(), String.t(), [term]) ::
          {:ok, module, atom, term} | {:error, reason}
  def apply(module_str, function_str, args)
      when is_binary(module_str) and is_binary(function_str) do
    arity = length(args)

    with {:ok, module} <- safe_module(module_str),
         {:ok, function} <- safe_function(function_str),
         true <- function_exported?(module, function, arity) do
      invoke(module, function, args)
    else
      false -> {:error, {:mfa_not_exported, module_str, function_str, arity}}
      {:error, _reason} = error -> error
    end
  end

  defp invoke(module, function, args) do
    {:ok, module, function, Kernel.apply(module, function, args)}
  rescue
    e -> {:error, {:mfa_raised, module, function, Exception.message(e)}}
  end

  defp safe_module(mod_str) do
    module = Module.safe_concat([mod_str])

    if Code.ensure_loaded?(module) do
      {:ok, module}
    else
      {:error, {:mfa_module_not_found, mod_str}}
    end
  rescue
    ArgumentError -> {:error, {:mfa_module_not_found, mod_str}}
  end

  defp safe_function(fun_str) do
    {:ok, String.to_existing_atom(fun_str)}
  rescue
    ArgumentError -> {:error, {:mfa_function_not_found, fun_str}}
  end
end
