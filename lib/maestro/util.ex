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

  @doc """
  Formats a `duration` (integer microseconds, as carried by step/testcase/
  suite results) for display: `"850 µs"`, `"12.4 ms"`, `"3.21 s"`,
  `"2m 05s"`. `nil` (not finished yet) renders as `"—"`.

  ## Examples

      iex> Maestro.Util.format_duration(850)
      "850 µs"
      iex> Maestro.Util.format_duration(12_400)
      "12.4 ms"
      iex> Maestro.Util.format_duration(3_210_000)
      "3.21 s"
      iex> Maestro.Util.format_duration(125_000_000)
      "2m 05s"
      iex> Maestro.Util.format_duration(nil)
      "—"
  """
  @spec format_duration(non_neg_integer | nil) :: String.t()
  def format_duration(nil), do: "—"
  def format_duration(us) when us < 1_000, do: "#{us} µs"
  def format_duration(us) when us < 1_000_000, do: "#{decimals(us / 1_000, 1)} ms"
  def format_duration(us) when us < 60_000_000, do: "#{decimals(us / 1_000_000, 2)} s"

  def format_duration(us) do
    total_seconds = div(us, 1_000_000)
    seconds = total_seconds |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{div(total_seconds, 60)}m #{seconds}s"
  end

  defp decimals(float, places), do: :erlang.float_to_binary(float, decimals: places)
end
