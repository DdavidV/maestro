defmodule MiniBank.Http.Router do
  @moduledoc """
  A small REST surface in front of `MiniBank.Bank`, mirroring the same
  operations the wire protocol exposes.
  """

  use Plug.Router

  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:match)
  plug(:dispatch)

  post "/accounts" do
    %{"account_number" => account_number, "owner" => owner} = conn.body_params
    initial_balance = Map.get(conn.body_params, "initial_balance", 0)

    case MiniBank.Bank.open_account(account_number, owner, initial_balance) do
      {:ok, account} -> json(conn, 201, MiniBank.Bank.account_fields(account))
      {:error, reason} -> error_json(conn, reason)
    end
  end

  post "/accounts/:account_number/deposit" do
    %{"amount" => amount} = conn.body_params

    case MiniBank.Bank.deposit(account_number, amount) do
      {:ok, account} -> json(conn, 200, MiniBank.Bank.account_fields(account))
      {:error, reason} -> error_json(conn, reason)
    end
  end

  post "/accounts/:account_number/withdraw" do
    %{"amount" => amount} = conn.body_params

    case MiniBank.Bank.withdraw(account_number, amount) do
      {:ok, account} -> json(conn, 200, MiniBank.Bank.account_fields(account))
      {:error, reason} -> error_json(conn, reason)
    end
  end

  post "/transfers" do
    %{"from" => from, "to" => to, "amount" => amount} = conn.body_params

    case MiniBank.Bank.transfer(from, to, amount) do
      {:ok, %{from: from_acc, to: to_acc}} ->
        json(conn, 200, %{
          "from" => MiniBank.Bank.account_fields(from_acc),
          "to" => MiniBank.Bank.account_fields(to_acc)
        })

      {:error, reason} ->
        error_json(conn, reason)
    end
  end

  get "/accounts/:account_number" do
    case MiniBank.Bank.get_balance(account_number) do
      {:ok, account} -> json(conn, 200, MiniBank.Bank.account_fields(account))
      {:error, reason} -> error_json(conn, reason)
    end
  end

  match _ do
    json(conn, 404, %{"error" => "not_found"})
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp error_json(conn, reason) do
    json(conn, status_for(reason), %{"error" => Atom.to_string(reason)})
  end

  defp status_for(:account_not_found), do: 404
  defp status_for(:account_number_taken), do: 409

  defp status_for(reason)
       when reason in [
              :invalid_amount,
              :invalid_initial_balance,
              :same_account,
              :insufficient_funds
            ],
       do: 422
end
