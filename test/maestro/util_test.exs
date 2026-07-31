defmodule Maestro.UtilTest do
  use ExUnit.Case, async: false

  describe "host_priv_dir/0" do
    test "defaults to Maestro's own priv_dir when host_app is unset" do
      assert Maestro.Util.host_priv_dir() == :code.priv_dir(:maestro) |> to_string()
    end

    test "resolves the named application's priv_dir when host_app is set" do
      Application.put_env(:maestro, :host_app, :maestro)
      on_exit(fn -> Application.delete_env(:maestro, :host_app) end)

      assert Maestro.Util.host_priv_dir() == :code.priv_dir(:maestro) |> to_string()
    end

    test "a host_app that doesn't name a loaded application raises" do
      Application.put_env(:maestro, :host_app, :totally_bogus_app_name)
      on_exit(fn -> Application.delete_env(:maestro, :host_app) end)

      assert_raise RuntimeError, ~r/does not name a loaded OTP application/, fn ->
        Maestro.Util.host_priv_dir()
      end
    end

    test "a non-atom host_app raises" do
      Application.put_env(:maestro, :host_app, "maestro")
      on_exit(fn -> Application.delete_env(:maestro, :host_app) end)

      assert_raise RuntimeError, ~r/must be an atom/, fn ->
        Maestro.Util.host_priv_dir()
      end
    end
  end
end
