defmodule Maestro.ResolverTest do
  use ExUnit.Case, async: true

  import Maestro.TestUtils
  alias Maestro.Resources.Resolver

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

  test "resolve suite reference with steps only" do
    suite = %{
      "testcases" => [
        %{
          "name" => "testcase 1",
          "steps" => [
            %{
              "client" => "http",
              "template" => "my_template",
              "dataset" => "my_dataset"
            }
          ]
        }
      ]
    }
    write_resource!("suites", "my_suite", suite)
    write_resource!("templates", "my_template", %{"clients" => ["http"], "payload" => %{"a" => 1}})
    write_resource!("datasets", "my_dataset", %{"data" => %{"foo" => "bar"}})
    assert(
      {:ok, %{
        "testcases" => [
          %{
            "name" => "testcase 1",
            "steps" => [
              %{
                "client" => "http",
                "dataset" => %{"data" => %{"foo" => "bar"}},
                "template" => %{"clients" => ["http"], "payload" => %{"a" => 1}}
              }
            ]
          }
        ]
       }} = Resolver.resolve("my_suite"))
  end

  test "resolve suite reference with scenario" do
    suite = %{
      "testcases" => [
        %{
          "name" => "testcase 1",
          "steps" => [
            %{
              "scenario" => "my_scenario",
              "dataset" => "my_dataset"
            }
          ]
        }
      ]
    }
    write_resource!("suites", "my_suite", suite)
    scenario = %{
      "steps" => [
        %{
          "client" => "http",
          "template" => "my_template"
        }
      ]
    }
    write_resource!("scenarios", "my_scenario", scenario)
    write_resource!("templates", "my_template", %{"clients" => ["http"], "payload" => %{"a" => 1}})
    write_resource!("datasets", "my_dataset", %{"data" => %{"foo" => "bar"}})
    assert(
      {:ok, %{
        "testcases" => [
            %{
              "name" => "testcase 1",
              "steps" => [
                %{
                  "dataset" => %{"data" => %{"foo" => "bar"}},
                  "scenario" => %{
                    "default_dataset" => %{"data" => %{"foo" => "bar"}},
                    "steps" => [
                      %{
                        "client" => "http",
                        "dataset" => %{"data" => %{"foo" => "bar"}},
                        "template" => %{
                          "clients" => ["http"],
                          "payload" => %{"a" => 1}
                        }
                      }
                    ]
                  }
                }
              ]
            }
          ]
        }} = Resolver.resolve("my_suite"))
  end

end
