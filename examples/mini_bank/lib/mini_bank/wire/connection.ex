defmodule MiniBank.Wire.Connection do
  @moduledoc """
  One process per accepted TCP connection: reads one newline-delimited
  JSON request line at a time, dispatches it to `MiniBank.Bank`,
  writes back one NDJSON response line, and loops until the socket closes.
  """

  @spec start(:gen_tcp.socket()) :: {:ok, pid}
  def start(socket) do
    pid = spawn(fn -> loop(socket) end)
    {:ok, pid}
  end

  defp loop(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, line} ->
        response = handle_line(line)
        :ok = :gen_tcp.send(socket, Jason.encode!(response) <> "\n")
        loop(socket)

      {:error, :closed} ->
        :ok
    end
  end

  defp handle_line(line) do
    with {:ok, decoded} <- Jason.decode(String.trim(line)),
         {:ok, op, args} <- fetch_op_and_args(decoded) do
      dispatch(op, args)
    else
      _ -> %{"status" => "error", "reason" => "invalid_request"}
    end
  end

  defp fetch_op_and_args(%{"op" => op, "args" => args})
       when is_binary(op) and is_map(args),
       do: {:ok, op, args}

  defp fetch_op_and_args(_), do: :error

  defp dispatch("open_account", %{"account_number" => acc, "owner" => owner} = args) do
    initial = Map.get(args, "initial_balance", 0)

    case MiniBank.Bank.open_account(acc, owner, initial) do
      {:ok, account} -> ok(MiniBank.Bank.account_fields(account))
      {:error, reason} -> error(reason)
    end
  end

  defp dispatch("deposit", %{"account_number" => acc, "amount" => amount}) do
    case MiniBank.Bank.deposit(acc, amount) do
      {:ok, account} -> ok(MiniBank.Bank.account_fields(account))
      {:error, reason} -> error(reason)
    end
  end

  defp dispatch("withdraw", %{"account_number" => acc, "amount" => amount}) do
    case MiniBank.Bank.withdraw(acc, amount) do
      {:ok, account} -> ok(MiniBank.Bank.account_fields(account))
      {:error, reason} -> error(reason)
    end
  end

  defp dispatch("transfer", %{"from" => from, "to" => to, "amount" => amount}) do
    case MiniBank.Bank.transfer(from, to, amount) do
      {:ok, %{from: from_acc, to: to_acc}} ->
        ok(%{
          "from" => MiniBank.Bank.account_fields(from_acc),
          "to" => MiniBank.Bank.account_fields(to_acc)
        })

      {:error, reason} ->
        error(reason)
    end
  end

  defp dispatch("get_balance", %{"account_number" => acc}) do
    case MiniBank.Bank.get_balance(acc) do
      {:ok, account} -> ok(MiniBank.Bank.account_fields(account))
      {:error, reason} -> error(reason)
    end
  end

  defp dispatch(_op, _args), do: %{"status" => "error", "reason" => "invalid_request"}

  defp ok(result), do: %{"status" => "ok", "result" => result}
  defp error(reason), do: %{"status" => "error", "reason" => Atom.to_string(reason)}
end
