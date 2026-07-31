defmodule MiniBank.Maestro.Generators do
  @moduledoc """
  MiniBank's own `Maestro.Generator` implementations:

    * `"account_number"` a fresh, unique account number, e.g.
      `"ACC-3F9A2B1C"`. Referenced via `{"$generated": "account_number"}`.
    * `"http_base_url" `MiniBank.Http.Endpoint`'s OS-assigned
      ephemeral port, as a full base URL, so a suite's HTTP steps never
      need to hardcode a port.
  """
  use Maestro.Generator

  generated_data "account_number", _args, _context do
    {:ok, "ACC-" <> (:crypto.strong_rand_bytes(4) |> Base.encode16())}
  end

  generated_data "http_base_url", _args, _context do
    {:ok, "http://127.0.0.1:#{MiniBank.Http.Endpoint.port()}"}
  end
end
