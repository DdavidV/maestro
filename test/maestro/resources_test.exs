defmodule Maestro.ResourcesTest do
  use ExUnit.Case, async: false

  import Maestro.WorkspaceFixtures
  alias Maestro.Resources

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
  end

  describe "fetch/3" do
    test "returns {:ok, data} for a valid suite", %{workspace: workspace} do
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

      resource_fixture!(workspace, :suite, "checkout_flow", suite)

      assert {:ok, data} = Resources.fetch(workspace, :suite, "checkout_flow")
      assert data["testcases"] |> hd() |> Map.fetch!("name") == "Add to cart"
    end

    test "resolves nested subdirectories", %{workspace: workspace} do
      dataset = %{"data" => %{"username" => "alice"}}
      resource_fixture!(workspace, :dataset, "checkout/seeded_users", dataset)

      assert {:ok, data} = Resources.fetch(workspace, :dataset, "checkout/seeded_users")
      assert data["data"]["username"] == "alice"
    end

    test "returns {:error, :not_found} for a missing file", %{workspace: workspace} do
      assert Resources.fetch(workspace, :suite, "does_not_exist") == {:error, :not_found}
      refute File.exists?(Path.join([workspace.root_dir, "suites", "does_not_exist.json"]))
    end

    test "returns {:error, :not_found} for unreadable/undecodable JSON", %{workspace: workspace} do
      file = Path.join([workspace.root_dir, "templates", "broken.json"])
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, "{not valid json")

      assert Resources.fetch(workspace, :template, "broken") == {:error, :not_found}
    end

    test "returns {:error, :not_found} when the path points at a directory", %{
      workspace: workspace
    } do
      dir_as_file = Path.join([workspace.root_dir, "scenarios", "oops.json"])
      File.mkdir_p!(dir_as_file)

      assert Resources.fetch(workspace, :scenario, "oops") == {:error, :not_found}
    end

    test "returns {:error, {:invalid, reasons}} for a schema-invalid file", %{
      workspace: workspace
    } do
      raw_resource_fixture!(workspace, :dataset, "empty", %{})

      assert {:error, {:invalid, reasons}} = Resources.fetch(workspace, :dataset, "empty")
      assert is_list(reasons)
      assert reasons != []
    end

    test "rejects paths that escape workspace.root_dir via ..", %{workspace: workspace} do
      outside = Path.join(workspace.root_dir, "..")
      escapee = Path.join(outside, "escapee.json")
      File.write!(escapee, Jason.encode!(%{"data" => %{"a" => 1}}))

      on_exit(fn -> File.rm(escapee) end)

      assert Resources.fetch(workspace, :dataset, "../escapee") == {:error, :not_found}
    end

    test "returns {:ok, data} for a valid test_plan", %{workspace: workspace} do
      test_plan = %{"id" => "nightly", "test_suites" => ["checkout/smoke"]}
      resource_fixture!(workspace, :test_plan, "nightly", test_plan)

      assert {:ok, data} = Resources.fetch(workspace, :test_plan, "nightly")
      assert data["test_suites"] == ["checkout/smoke"]
    end

    test "an edit to a file takes effect on the next fetch, no reload needed", %{
      workspace: workspace
    } do
      resource_fixture!(workspace, :template, "greeting", %{
        "clients" => ["http"],
        "payload" => %{"a" => 1}
      })

      assert {:ok, %{"payload" => %{"a" => 1}}} =
               Resources.fetch(workspace, :template, "greeting")

      resource_fixture!(workspace, :template, "greeting", %{
        "clients" => ["http"],
        "payload" => %{"a" => 2}
      })

      assert {:ok, %{"payload" => %{"a" => 2}}} =
               Resources.fetch(workspace, :template, "greeting")
    end
  end

  describe "list/2" do
    test "lists every resource of a kind, with name/description/tags parsed", %{
      workspace: workspace
    } do
      resource_fixture!(workspace, :dataset, "seeded_users", %{
        "name" => "Seeded Users",
        "description" => "All seeded users",
        "data" => %{"username" => "alice"}
      })

      resource_fixture!(workspace, :dataset, "checkout/other", %{"data" => %{"a" => 1}})

      entries = Resources.list(workspace, :dataset)
      assert length(entries) == 2

      seeded = Enum.find(entries, &(&1.path == "seeded_users"))
      assert seeded.name == "Seeded Users"
      assert seeded.description == "All seeded users"
      assert seeded.tags == []

      other = Enum.find(entries, &(&1.path == "checkout/other"))
      assert other.name == nil
    end

    test "returns [] for a kind with no files at all", %{workspace: workspace} do
      assert Resources.list(workspace, :suite) == []
    end

    test "skips a file that fails to parse/validate rather than raising", %{workspace: workspace} do
      raw_resource_fixture!(workspace, :dataset, "broken", %{})
      resource_fixture!(workspace, :dataset, "fine", %{"data" => %{"a" => 1}})

      entries = Resources.list(workspace, :dataset)
      assert Enum.map(entries, & &1.path) == ["fine"]
    end
  end

  describe "list_dir/3" do
    test "lists only immediate children, not nested contents, of the root", %{
      workspace: workspace
    } do
      resource_fixture!(workspace, :dataset, "top_level", %{"data" => %{"a" => 1}})
      resource_fixture!(workspace, :dataset, "checkout/nested", %{"data" => %{"a" => 1}})

      %{folders: folders, entries: entries} = Resources.list_dir(workspace, :dataset, "")

      assert folders == ["checkout"]
      assert Enum.map(entries, & &1.path) == ["top_level"]
    end

    test "lists a subdirectory's own contents when given a dir path", %{workspace: workspace} do
      resource_fixture!(workspace, :dataset, "checkout/nested", %{"data" => %{"a" => 1}})

      resource_fixture!(workspace, :dataset, "checkout/deeper/double_nested", %{
        "data" => %{"a" => 1}
      })

      %{folders: folders, entries: entries} = Resources.list_dir(workspace, :dataset, "checkout")

      assert folders == ["deeper"]
      assert Enum.map(entries, & &1.path) == ["checkout/nested"]
    end

    test "returns empty folders/entries for a directory that doesn't exist", %{
      workspace: workspace
    } do
      assert Resources.list_dir(workspace, :dataset, "does_not_exist") == %{
               folders: [],
               entries: []
             }
    end

    test "skips a file that fails to parse/validate rather than raising", %{workspace: workspace} do
      raw_resource_fixture!(workspace, :dataset, "broken", %{})
      resource_fixture!(workspace, :dataset, "fine", %{"data" => %{"a" => 1}})

      %{entries: entries} = Resources.list_dir(workspace, :dataset, "")
      assert Enum.map(entries, & &1.path) == ["fine"]
    end

    test "rejects a dir path that escapes workspace.root_dir via ..", %{workspace: workspace} do
      resource_fixture!(workspace, :dataset, "seeded_users", %{"data" => %{"a" => 1}})

      assert Resources.list_dir(workspace, :dataset, "../../etc") == %{folders: [], entries: []}
    end
  end

  describe "write/4" do
    test "writes valid data, immediately re-fetchable", %{workspace: workspace} do
      dataset = %{"data" => %{"a" => 1}}
      assert :ok = Resources.write(workspace, :dataset, "new_dataset", dataset)
      assert {:ok, ^dataset} = Resources.fetch(workspace, :dataset, "new_dataset")
    end

    test "creates nested subdirectories as needed", %{workspace: workspace} do
      dataset = %{"data" => %{"a" => 1}}
      assert :ok = Resources.write(workspace, :dataset, "nested/deep/dataset", dataset)
      assert {:ok, ^dataset} = Resources.fetch(workspace, :dataset, "nested/deep/dataset")
    end

    test "rejects schema-invalid data before touching disk", %{workspace: workspace} do
      assert {:error, {:invalid, reasons}} = Resources.write(workspace, :dataset, "bad", %{})
      assert reasons != []
      refute File.exists?(Path.join([workspace.root_dir, "datasets", "bad.json"]))
    end

    test "an invalid write does not clobber an existing valid file at the same path", %{
      workspace: workspace
    } do
      original = %{"data" => %{"a" => 1}}
      :ok = Resources.write(workspace, :dataset, "existing", original)

      assert {:error, {:invalid, _reasons}} =
               Resources.write(workspace, :dataset, "existing", %{})

      assert {:ok, ^original} = Resources.fetch(workspace, :dataset, "existing")
    end
  end

  describe "delete/3" do
    test "deletes an existing resource", %{workspace: workspace} do
      resource_fixture!(workspace, :dataset, "to_delete", %{"data" => %{"a" => 1}})
      assert :ok = Resources.delete(workspace, :dataset, "to_delete")
      assert Resources.fetch(workspace, :dataset, "to_delete") == {:error, :not_found}
    end

    test "{:error, :not_found} for a resource that doesn't exist", %{workspace: workspace} do
      assert Resources.delete(workspace, :dataset, "does_not_exist") == {:error, :not_found}
    end
  end
end
