defmodule Maestro.TestClient do
  @moduledoc false
  use Maestro.Client, name: "test_client"

  def init_client do
    Agent.start_link(fn -> %{calls: []} end)
  end

  def init(agent, rendered) do
    Agent.update(agent, fn state -> %{state | calls: [{:init, rendered} | state.calls]} end)
    {:ok, agent}
  end

  def send(agent, rendered) do
    Agent.update(agent, fn state -> %{state | calls: [{:send, rendered} | state.calls]} end)
    {:ok, %{"echo" => rendered}}
  end

  def calls(agent) do
    Agent.get(agent, & &1.calls) |> Enum.reverse()
  end
end

defmodule Maestro.TestClientNoOptional do
  @moduledoc false
  use Maestro.Client, name: "test_client_no_optional"

  def send(_call_state, rendered) do
    {:ok, %{"echo" => rendered}}
  end
end

defmodule Maestro.TestClientFailingInit do
  @moduledoc false
  use Maestro.Client, name: "test_client_failing_init"

  def init_client do
    {:error, :boom}
  end

  def send(_call_state, rendered) do
    {:ok, %{"echo" => rendered}}
  end
end
