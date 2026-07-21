defmodule Maestro.ResourcesTest do
  use ExUnit.Case, async: false

  import Maestro.TestUtils
  alias Maestro.Resources

  setup do
    dir =
      Path.join(System.tmp_dir!(), "maestro_registry_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    previous = Application.get_env(:maestro, :resource_dir)
    Application.put_env(:maestro, :resource_dir, dir)

    on_exit(fn ->
      File.rm_rf!(dir)

      if previous do
        Application.put_env(:maestro, :resource_dir, previous)
      else
        Application.delete_env(:maestro, :resource_dir)
      end
    end)

    %{dir: dir}
  end

  describe "resource_dir/0" do
    test "reads config :maestro, :resource_dir", %{dir: dir} do
      assert Resources.resource_dir() == dir
    end

    test "falls back to priv/resources under Maestro's priv_dir when unset" do
      Application.delete_env(:maestro, :resource_dir)
      expected = Path.join(:code.priv_dir(:maestro), "resources")
      assert Resources.resource_dir() == expected
    end
  end

  describe "fetch/2" do
    test "returns {:ok, data} for a valid suite" do
      suite = %{
        "id" => "checkout-flow",
        "testcases" => [
          %{
            "id" => "add-to-cart",
            "name" => "Add to cart",
            "steps" => [
              %{
                "client" => "http",
                "template" => "add_to_cart_request",
                "dataset" => %{"data" => %{"sku" => "ABC123", "qty" => 1}}
              }
            ]
          }
        ]
      }

      write_resource!("suites", "checkout_flow", suite)

      assert {:ok, data} = Resources.fetch(:suite, "checkout_flow")
      assert data["testcases"] |> hd() |> Map.fetch!("name") == "Add to cart"
    end

    test "resolves nested subdirectories" do
      dataset = %{"data" => %{"username" => "alice"}}
      write_resource!("datasets", "checkout/seeded_users", dataset)

      assert {:ok, data} = Resources.fetch(:dataset, "checkout/seeded_users")
      assert data["data"]["username"] == "alice"
    end

    test "returns {:error, :not_found} for a missing file", %{dir: dir} do
      assert Resources.fetch(:suite, "does_not_exist") == {:error, :not_found}
      refute File.exists?(Path.join([dir, "suites", "does_not_exist.json"]))
    end

    test "returns {:error, :not_found} for unreadable/undecodable JSON", %{dir: dir} do
      file = Path.join([dir, "templates", "broken.json"])
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, "{not valid json")

      assert Resources.fetch(:template, "broken") == {:error, :not_found}
    end

    test "returns {:error, :not_found} when the path points at a directory", %{dir: dir} do
      dir_as_file = Path.join([dir, "scenarios", "oops.json"])
      File.mkdir_p!(dir_as_file)

      assert Resources.fetch(:scenario, "oops") == {:error, :not_found}
    end

    test "returns {:error, {:invalid, reasons}} for a schema-invalid file" do
      write_resource!("datasets", "empty", %{})

      assert {:error, {:invalid, reasons}} = Resources.fetch(:dataset, "empty")
      assert is_list(reasons)
      assert reasons != []
    end

    test "rejects paths that escape resource_dir via ..", %{dir: dir} do
      outside = Path.join(dir, "..")
      escapee = Path.join(outside, "escapee.json")
      File.write!(escapee, Jason.encode!(%{"data" => %{"a" => 1}}))

      on_exit(fn -> File.rm(escapee) end)

      assert Resources.fetch(:dataset, "../escapee") == {:error, :not_found}
    end

    test "an edit to a file takes effect on the next fetch, no reload needed" do
      write_resource!("templates", "greeting", %{"clients" => ["http"], "payload" => %{"a" => 1}})
      assert {:ok, %{"payload" => %{"a" => 1}}} = Resources.fetch(:template, "greeting")

      write_resource!("templates", "greeting", %{"clients" => ["http"], "payload" => %{"a" => 2}})
      assert {:ok, %{"payload" => %{"a" => 2}}} = Resources.fetch(:template, "greeting")
    end
  end
end
