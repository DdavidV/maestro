defmodule MiniBank.Bank do
  @moduledoc """
  In-memory banking domain: open accounts, deposit/withdraw, and transfer
  funds between them. Every mutation goes through this `GenServer`'s
  `handle_call`, serializing concurrent writes (a transfer's debit+credit
  happens atomically within one call, so no other process can ever observe
  a half-applied transfer). Account data itself lives in an ETS table this
  process owns, so a read can either round-trip through this process (`get_balance/1`)
  or bypass it entirely via a direct `:ets.lookup/2` against `table/0`.
  """

  use GenServer

  alias MiniBank.Bank.Account

  @table :mini_bank_accounts

  # A small artificial delay on every mutation, purely so a run watched live
  # (e.g. in Maestro's web GUI) visibly steps through testcases one at a
  # time instead of finishing faster than a human can see anything happen.
  @simulated_latency_ms 400

  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc "The ETS table backing this bank's accounts, for a direct (non-GenServer) read."
  @spec table() :: :ets.table()
  def table, do: @table

  @doc "Maps an `Account.t()` to the plain string-keyed map every client response uses."
  @spec account_fields(Account.t()) :: %{String.t() => term}
  def account_fields(%Account{} = account) do
    %{
      "account_number" => account.account_number,
      "owner" => account.owner,
      "balance" => account.balance
    }
  end

  @spec open_account(String.t(), String.t(), integer) ::
          {:ok, Account.t()} | {:error, :account_number_taken | :invalid_initial_balance}
  def open_account(account_number, owner, initial_balance \\ 0) do
    GenServer.call(__MODULE__, {:open_account, account_number, owner, initial_balance})
  end

  @spec deposit(String.t(), integer) ::
          {:ok, Account.t()} | {:error, :account_not_found | :invalid_amount}
  def deposit(account_number, amount) do
    GenServer.call(__MODULE__, {:deposit, account_number, amount})
  end

  @spec withdraw(String.t(), integer) ::
          {:ok, Account.t()}
          | {:error, :account_not_found | :invalid_amount | :insufficient_funds}
  def withdraw(account_number, amount) do
    GenServer.call(__MODULE__, {:withdraw, account_number, amount})
  end

  @spec transfer(String.t(), String.t(), integer) ::
          {:ok, %{from: Account.t(), to: Account.t()}}
          | {:error, :account_not_found | :invalid_amount | :insufficient_funds | :same_account}
  def transfer(from, to, amount) do
    GenServer.call(__MODULE__, {:transfer, from, to, amount})
  end

  @spec get_balance(String.t()) :: {:ok, Account.t()} | {:error, :account_not_found}
  def get_balance(account_number) do
    Process.sleep(@simulated_latency_ms)

    case :ets.lookup(@table, account_number) do
      [{^account_number, account}] -> {:ok, account}
      [] -> {:error, :account_not_found}
    end
  end

  @impl true
  def init(:ok) do
    :ets.new(@table, [:set, :protected, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:open_account, account_number, owner, initial_balance}, _from, state) do
    Process.sleep(@simulated_latency_ms)

    cond do
      not valid_initial_balance?(initial_balance) ->
        {:reply, {:error, :invalid_initial_balance}, state}

      account_exists?(account_number) ->
        {:reply, {:error, :account_number_taken}, state}

      true ->
        account = %Account{account_number: account_number, owner: owner, balance: initial_balance}
        :ets.insert(@table, {account_number, account})
        {:reply, {:ok, account}, state}
    end
  end

  def handle_call({:deposit, account_number, amount}, _from, state) do
    Process.sleep(@simulated_latency_ms)

    with :ok <- validate_amount(amount),
         {:ok, account} <- fetch_account(account_number) do
      updated = %{account | balance: account.balance + amount}
      :ets.insert(@table, {account_number, updated})
      {:reply, {:ok, updated}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:withdraw, account_number, amount}, _from, state) do
    Process.sleep(@simulated_latency_ms)

    with :ok <- validate_amount(amount),
         {:ok, account} <- fetch_account(account_number),
         :ok <- validate_sufficient_funds(account, amount) do
      updated = %{account | balance: account.balance - amount}
      :ets.insert(@table, {account_number, updated})
      {:reply, {:ok, updated}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:transfer, from, to, amount}, _from, state) do
    Process.sleep(@simulated_latency_ms)

    cond do
      from == to ->
        {:reply, {:error, :same_account}, state}

      true ->
        with :ok <- validate_amount(amount),
             {:ok, from_account} <- fetch_account(from),
             {:ok, to_account} <- fetch_account(to),
             :ok <- validate_sufficient_funds(from_account, amount) do
          updated_from = %{from_account | balance: from_account.balance - amount}
          updated_to = %{to_account | balance: to_account.balance + amount}
          :ets.insert(@table, {from, updated_from})
          :ets.insert(@table, {to, updated_to})
          {:reply, {:ok, %{from: updated_from, to: updated_to}}, state}
        else
          {:error, reason} -> {:reply, {:error, reason}, state}
        end
    end
  end

  defp account_exists?(account_number) do
    match?([_], :ets.lookup(@table, account_number))
  end

  defp fetch_account(account_number) do
    case :ets.lookup(@table, account_number) do
      [{^account_number, account}] -> {:ok, account}
      [] -> {:error, :account_not_found}
    end
  end

  defp valid_initial_balance?(balance), do: is_integer(balance) and balance >= 0

  defp validate_amount(amount) when is_integer(amount) and amount > 0, do: :ok
  defp validate_amount(_amount), do: {:error, :invalid_amount}

  defp validate_sufficient_funds(%Account{balance: balance}, amount) when amount <= balance,
    do: :ok

  defp validate_sufficient_funds(_account, _amount), do: {:error, :insufficient_funds}
end
