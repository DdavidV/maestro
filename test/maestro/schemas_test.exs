defmodule Maestro.SchemasTest do
  use ExUnit.Case, async: true

  alias Maestro.Resources.Schemas

  describe "validate/2 (:suite)" do
    test "accepts a minimal valid suite" do
      suite = %{
        "name" => "Checkout Flow",
        "testcases" => [
          %{
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

      assert Schemas.validate(:suite, suite) == :ok
    end

    test "accepts every worked example from suite.schema.json" do
      for example <- examples_for("suite") do
        assert Schemas.validate(:suite, example) == :ok
      end
    end

    test "rejects a suite missing testcases" do
      assert {:error, errors} = Schemas.validate(:suite, %{"name" => "Checkout Flow"})
      assert Enum.any?(errors, fn {message, _path} -> message =~ "testcases" end)
    end

    test "accepts a suite without a name" do
      suite = %{
        "testcases" => [
          %{
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

      assert Schemas.validate(:suite, suite) == :ok
    end

    test "rejects a suite whose step is neither a template-step nor a scenario-call" do
      suite = %{
        "name" => "Checkout Flow",
        "testcases" => [
          %{"name" => "Add to cart", "steps" => [%{"foo" => "bar"}]}
        ]
      }

      assert {:error, _errors} = Schemas.validate(:suite, suite)
    end

    test "rejects a testcase step missing its required dataset" do
      suite = %{
        "name" => "Checkout Flow",
        "testcases" => [
          %{
            "name" => "Add to cart",
            "steps" => [%{"client" => "http", "template" => "add_to_cart_request"}]
          }
        ]
      }

      assert {:error, _errors} = Schemas.validate(:suite, suite)
    end
  end

  describe "validate/2 (:scenario)" do
    test "accepts every worked example from scenario.schema.json" do
      for example <- examples_for("scenario") do
        assert Schemas.validate(:scenario, example) == :ok
      end
    end

    test "rejects a scenario step that declares its own dataset" do
      scenario = %{
        "name" => "login_and_get_token",
        "steps" => [
          %{
            "client" => "http",
            "template" => "login_request",
            "dataset" => %{"username" => "user"}
          }
        ]
      }

      assert {:error, _errors} = Schemas.validate(:scenario, scenario)
    end

    test "accepts a scenario step without a dataset" do
      scenario = %{
        "name" => "login_and_get_token",
        "default_dataset" => %{"data" => %{"password" => "default-test-password"}},
        "steps" => [%{"client" => "http", "template" => "login_request"}]
      }

      assert Schemas.validate(:scenario, scenario) == :ok
    end

    test "rejects a scenario missing steps" do
      assert {:error, _errors} = Schemas.validate(:scenario, %{"name" => "login_and_get_token"})
    end

    test "accepts a scenario without a name" do
      scenario = %{
        "default_dataset" => %{"data" => %{"password" => "default-test-password"}},
        "steps" => [%{"client" => "http", "template" => "login_request"}]
      }

      assert Schemas.validate(:scenario, scenario) == :ok
    end
  end

  describe "validate/2 (:step)" do
    test "accepts every worked example from step.schema.json" do
      for example <- examples_for("step") do
        assert Schemas.validate(:step, example) == :ok
      end
    end

    test "accepts a template-step with an inline dataset" do
      step = %{
        "client" => "kafka",
        "template" => "order_created_v1",
        "dataset" => %{"data" => %{"order_id" => "1"}}
      }

      assert Schemas.validate(:step, step) == :ok
    end

    test "accepts a template-step whose dataset references a named dataset" do
      step = %{
        "client" => "http",
        "template" => "create_account_request",
        "dataset" => "seeded_users"
      }

      assert Schemas.validate(:step, step) == :ok
    end

    test "accepts a scenario-call step" do
      step = %{
        "scenario" => "login_and_get_token",
        "dataset" => %{"data" => %{"username" => "alice"}}
      }

      assert Schemas.validate(:step, step) == :ok
    end

    test "rejects a step with neither client/template nor scenario" do
      assert {:error, _errors} = Schemas.validate(:step, %{"name" => "does nothing"})
    end

    test "rejects a step mixing both variants" do
      step = %{
        "client" => "http",
        "template" => "t",
        "dataset" => %{},
        "scenario" => "login_and_get_token"
      }

      assert {:error, _errors} = Schemas.validate(:step, step)
    end

    test "rejects an assert entry missing properties" do
      step = %{
        "client" => "http",
        "template" => "t",
        "dataset" => %{},
        "assert" => [%{"provider" => "db"}]
      }

      assert {:error, _errors} = Schemas.validate(:step, step)
    end
  end

  describe "validate/2 (:dataset)" do
    test "accepts every worked example from dataset.schema.json" do
      for example <- examples_for("dataset") do
        assert Schemas.validate(:dataset, example) == :ok
      end
    end

    test "rejects a dataset with neither data nor rows" do
      assert {:error, _errors} = Schemas.validate(:dataset, %{"name" => "empty"})
    end

    test "accepts a dataset without a name" do
      assert Schemas.validate(:dataset, %{"data" => %{"a" => 1}}) == :ok
    end
  end

  describe "validate/2 (:template)" do
    test "accepts every worked example from template.schema.json" do
      for example <- examples_for("template") do
        assert Schemas.validate(:template, example) == :ok
      end
    end

    test "accepts a template with only a payload (no options)" do
      template = %{"name" => "x", "clients" => ["http"], "payload" => %{"a" => 1}}
      assert Schemas.validate(:template, template) == :ok
    end

    test "rejects a template missing payload" do
      template = %{"name" => "x", "clients" => ["http"], "options" => %{"url" => "y"}}
      assert {:error, _errors} = Schemas.validate(:template, template)
    end

    test "rejects a template with an empty clients list" do
      template = %{"name" => "x", "clients" => [], "payload" => %{}}
      assert {:error, _errors} = Schemas.validate(:template, template)
    end

    test "accepts a template without a name" do
      template = %{"clients" => ["http"], "payload" => %{"a" => 1}}
      assert Schemas.validate(:template, template) == :ok
    end
  end

  defp examples_for(name) do
    Path.join(:code.priv_dir(:maestro), "schemas")
    |> Path.join("#{name}.schema.json")
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("examples")
  end
end
