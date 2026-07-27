defmodule Maestro.TestGenerator do
  @moduledoc false
  use Maestro.Generator

  # Backed by System.unique_integer/1 so tests can observe that a
  # generator is called fresh every render/2 call (not cached/reused).
  generated_data "test_counter", _args, _context do
    {:ok, System.unique_integer([:positive, :monotonic])}
  end

  # Echoes back exactly the (already-interpolated) args it received, so
  # tests can assert on args interpolation without any process/agent state.
  generated_data "test_echo_args", args, _context do
    {:ok, args}
  end

  generated_data "test_always_fails", _args, _context do
    {:error, :always_fails}
  end

  generated_data "test_always_raises", _args, _context do
    raise "test generator boom"
  end
end
