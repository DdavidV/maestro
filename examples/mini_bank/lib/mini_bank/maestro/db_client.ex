defmodule MiniBank.Maestro.DbClient do
  @moduledoc """
  Maestro client that imitates querying a database, registered as
  `"db_client"`. The request/response shape reads like a DB query, but
  it's implemented as a direct `:ets.lookup/2` against `MiniBank.Bank`'s
  own table. The read-replica-style counterpart to `MiniBank.Maestro.WireClient`'s
  transactional path: same underlying data, a different, read-only access pattern.

  Only one operation is supported (`get_account`, a read):

  ```json
  {
    "clients": ["db_client"],
    "payload": {
      "op": "get_account",
      "args": { "account_number": "{{account_number}}" }
    }
  }
  ```

  Response, mirroring a query result row:

  ```json
  {"status": "ok", "row": {"account_number": "...", "owner": "...", "balance": 12345}}
  {"status": "error", "reason": "account_not_found"}
  ```
  """

  use Maestro.Client, name: "db_client"

  @impl true
  def send(_call_state, %{
        "payload" => %{"op" => "get_account", "args" => %{"account_number" => account_number}}
      }) do
    case :ets.lookup(MiniBank.Bank.table(), account_number) do
      [{^account_number, account}] ->
        {:ok, %{"status" => "ok", "row" => MiniBank.Bank.account_fields(account)}}

      [] ->
        {:ok, %{"status" => "error", "reason" => "account_not_found"}}
    end
  end

  def send(_call_state, rendered) do
    {:error, {:invalid_payload, rendered["payload"]}}
  end
end
