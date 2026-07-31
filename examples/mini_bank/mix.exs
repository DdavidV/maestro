defmodule MiniBank.MixProject do
  use Mix.Project

  def project do
    [
      app: :mini_bank,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {MiniBank.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:maestro, path: "../.."},
      {:plug, "~> 1.18"},
      {:bandit, "~> 1.5"}
    ]
  end
end
