defmodule MiniBank.Bank.Account do
  @moduledoc """
  A single bank account: a stable account number, its owner's display name,
  and its current balance, always an integer minor-unit value (e.g. cents),
  never a float -- exactly what `MiniBank.Maestro.MoneyEquals` exists to
  check safely.
  """

  @type t :: %__MODULE__{
          account_number: String.t(),
          owner: String.t(),
          balance: integer
        }

  @enforce_keys [:account_number, :owner]
  defstruct account_number: nil, owner: nil, balance: 0
end
