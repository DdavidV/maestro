defmodule Maestro.Util do
  @moduledoc """
  Small helpers shared by multiple modules.
  """

  @doc """
  The `priv_dir` Maestro's own runtime data (the workspace registry,
  generated reports, ...) is stored under by default: the OTP application
  named by `config :maestro, :host_app`, if set, or Maestro's own
  `priv_dir` otherwise.

  There's no reliable way for Maestro to discover which application
  embeds it at runtime (especially in a compiled release, where `Mix` and
  its project metadata aren't available at all) an embedding host must
  say so explicitly via `host_app` to get its *own* `priv_dir` used
  instead of Maestro's.

  Raises if `host_app` is set but doesn't name a real, loaded application
  (or isn't an atom) a misconfigured `host_app` is a mistake worth
  failing loudly for at boot, not one to silently paper over.
  """
  @spec host_priv_dir() :: String.t()
  def host_priv_dir do
    case Application.get_env(:maestro, :host_app) do
      nil -> :code.priv_dir(:maestro) |> List.to_string()
      host_app when is_atom(host_app) -> resolve_host_priv_dir(host_app)
      other -> raise_invalid_host_app(other, "must be an atom, got: #{inspect(other)}")
    end
  end

  defp resolve_host_priv_dir(host_app) do
    case :code.priv_dir(host_app) do
      priv_dir when is_list(priv_dir) ->
        List.to_string(priv_dir)

      {:error, :bad_name} ->
        raise_invalid_host_app(
          host_app,
          "does not name a loaded OTP application (:code.priv_dir/1 returned " <>
            "{:error, :bad_name})"
        )
    end
  end

  defp raise_invalid_host_app(host_app, reason) do
    raise """
    config :maestro, host_app: #{inspect(host_app)} #{reason}.

    Set host_app to the OTP application name of the app embedding Maestro \
    (e.g. the :app value in your own mix.exs), or remove the config entirely \
    to default to Maestro's own priv_dir instead.
    """
  end
end
