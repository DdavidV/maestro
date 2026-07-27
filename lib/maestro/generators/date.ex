defmodule Maestro.Generators.Date do
  @moduledoc """
  Built-in generator(s) for dates. See each `generated_data` block below
  for what it's registered as and how to call it.
  """

  use Maestro.Generator

  # `{"$generated": "today"}` — zero-arg form, returns today's date as an
  # ISO-8601 string.
  # `{"$generated": {"name": "today", "args": [7]}}` — optional single
  # arg is a signed day offset, as an integer or a string; `[7]` → 7 days
  # from today, `[-3]` → 3 days ago. `args` are interpolated first (see
  # `Maestro.Core.Interpolation`), so a `{{placeholder}}` offset from the
  # dataset/save context works too, arriving here as a string.
  generated_data "today", args, _context do
    case args do
      [] ->
        {:ok, Date.to_iso8601(Date.utc_today())}

      [offset] when is_integer(offset) ->
        {:ok, Date.utc_today() |> Date.add(offset) |> Date.to_iso8601()}

      [offset] when is_binary(offset) ->
        case Integer.parse(offset) do
          {int, ""} -> {:ok, Date.utc_today() |> Date.add(int) |> Date.to_iso8601()}
          _ -> {:error, {:invalid_offset, offset}}
        end

      _ ->
        {:error, {:invalid_args, args}}
    end
  end
end
