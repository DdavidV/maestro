defmodule Maestro.ApplicationTest do
  use ExUnit.Case, async: false

  describe "endpoint config, as filled in by Application.start/2" do
    test "MaestroWeb.Endpoint has a usable http/secret_key_base config" do
      config = Application.get_env(:maestro, MaestroWeb.Endpoint)

      assert config != nil

      assert Keyword.has_key?(config, :http)
      assert Keyword.has_key?(config, :secret_key_base)
      assert byte_size(Keyword.fetch!(config, :secret_key_base)) >= 64

      assert config[:render_errors][:formats][:html] == MaestroWeb.ErrorHTML
    end
  end

  describe "ex_json_schema config, as filled in by Application.start/2" do
    test "is set regardless of the host app's own config" do
      assert Application.get_env(:ex_json_schema, :remote_schema_resolver) ==
               {Maestro.Resources.Schemas, :load_and_resolve_ref}

      assert is_function(Application.get_env(:ex_json_schema, :decode_json), 1)
    end
  end
end
