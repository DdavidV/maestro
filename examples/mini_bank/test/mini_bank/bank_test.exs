defmodule MiniBank.BankTest do
  use ExUnit.Case, async: false

  alias MiniBank.Bank

  defp fresh_account_number, do: "TEST-" <> (:crypto.strong_rand_bytes(4) |> Base.encode16())

  test "open_account then get_balance round-trips" do
    acc = fresh_account_number()
    assert {:ok, _} = Bank.open_account(acc, "Alice", 10_000)
    assert {:ok, %{account_number: ^acc, owner: "Alice", balance: 10_000}} = Bank.get_balance(acc)
  end

  test "the ETS table backing MiniBank.Bank reflects the same data GenServer reads see" do
    acc = fresh_account_number()
    {:ok, _} = Bank.open_account(acc, "Alice", 500)

    assert [{^acc, %MiniBank.Bank.Account{balance: 500}}] = :ets.lookup(Bank.table(), acc)
  end

  test "opening the same account number twice fails" do
    acc = fresh_account_number()
    assert {:ok, _} = Bank.open_account(acc, "Alice", 0)
    assert {:error, :account_number_taken} = Bank.open_account(acc, "Alice", 0)
  end

  test "opening an account with a negative initial balance fails" do
    acc = fresh_account_number()
    assert {:error, :invalid_initial_balance} = Bank.open_account(acc, "Alice", -1)
  end

  test "deposit increases balance" do
    acc = fresh_account_number()
    {:ok, _} = Bank.open_account(acc, "Alice", 1_000)
    assert {:ok, %{balance: 1_500}} = Bank.deposit(acc, 500)
  end

  test "deposit of a non-positive amount fails" do
    acc = fresh_account_number()
    {:ok, _} = Bank.open_account(acc, "Alice", 1_000)
    assert {:error, :invalid_amount} = Bank.deposit(acc, 0)
    assert {:error, :invalid_amount} = Bank.deposit(acc, -5)
  end

  test "withdraw decreases balance" do
    acc = fresh_account_number()
    {:ok, _} = Bank.open_account(acc, "Alice", 1_000)
    assert {:ok, %{balance: 400}} = Bank.withdraw(acc, 600)
  end

  test "withdraw more than balance fails with insufficient_funds" do
    acc = fresh_account_number()
    {:ok, _} = Bank.open_account(acc, "Alice", 100)
    assert {:error, :insufficient_funds} = Bank.withdraw(acc, 101)
  end

  test "transfer moves funds between two accounts" do
    from = fresh_account_number()
    to = fresh_account_number()
    {:ok, _} = Bank.open_account(from, "Alice", 1_000)
    {:ok, _} = Bank.open_account(to, "Bob", 0)

    assert {:ok, %{from: %{balance: 700}, to: %{balance: 300}}} =
             Bank.transfer(from, to, 300)
  end

  test "transfer with insufficient funds fails and changes nothing" do
    from = fresh_account_number()
    to = fresh_account_number()
    {:ok, _} = Bank.open_account(from, "Alice", 100)
    {:ok, _} = Bank.open_account(to, "Bob", 0)

    assert {:error, :insufficient_funds} = Bank.transfer(from, to, 101)
    assert {:ok, %{balance: 100}} = Bank.get_balance(from)
    assert {:ok, %{balance: 0}} = Bank.get_balance(to)
  end

  test "transfer to the same account is rejected" do
    acc = fresh_account_number()
    {:ok, _} = Bank.open_account(acc, "Alice", 100)
    assert {:error, :same_account} = Bank.transfer(acc, acc, 10)
  end

  test "unknown account returns account_not_found" do
    assert {:error, :account_not_found} = Bank.get_balance("does-not-exist")
    assert {:error, :account_not_found} = Bank.deposit("does-not-exist", 100)
  end
end
