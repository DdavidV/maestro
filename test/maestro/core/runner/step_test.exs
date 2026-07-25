defmodule Maestro.Core.Runner.StepTest do
  use ExUnit.Case, async: false

  alias Maestro.Assert.Registry, as: AssertRegistry
  alias Maestro.Client.Error, as: ClientError
  alias Maestro.Client.Registry, as: ClientRegistry
  alias Maestro.Core.Runner.Step

  setup do
    :ok = ClientRegistry.load!()
    :ok = AssertRegistry.load!()
    :ok
  end

  defp template_step(opts) do
    %{
      name: Keyword.get(opts, :name),
      client: Keyword.get(opts, :client, "test_client_no_optional"),
      template: %{
        payload: Keyword.fetch!(opts, :payload),
        options: Keyword.get(opts, :options, %{})
      },
      dataset: Keyword.fetch!(opts, :dataset),
      save: Keyword.get(opts, :save, []),
      assert: Keyword.get(opts, :assert, [])
    }
    |> Enum.reject(fn {_k, v} -> v == nil end)
    |> Map.new()
  end

  describe "run_steps/2 basic dispatch" do
    test "renders the payload/options and dispatches to the named client" do
      step =
        template_step(
          payload: %{"foo" => "{{foo}}"},
          dataset: %{data: %{"foo" => "bar"}}
        )

      assert {:ok, {[result], _saved}} = Step.run_steps([step])
      assert result.status == :ok
      assert result.client == "test_client_no_optional"
      assert result.rendered == %{"payload" => %{"foo" => "bar"}, "options" => %{}}
      assert result.response == %{"echo" => result.rendered}
    end

    test "options are rendered too and passed through to the client" do
      step =
        template_step(
          payload: %{},
          options: %{"url" => "https://example.com/{{id}}"},
          dataset: %{data: %{"id" => "42"}}
        )

      assert {:ok, {[result], _saved}} = Step.run_steps([step])
      assert result.rendered["options"] == %{"url" => "https://example.com/42"}
    end
  end

  describe "run_steps/2 row iteration" do
    test "a step with a rows dataset runs once per row, in order" do
      step =
        template_step(
          payload: %{"user" => "{{username}}"},
          dataset: %{rows: [%{"username" => "alice"}, %{"username" => "bob"}]}
        )

      assert {:ok, {[first, second], _saved}} = Step.run_steps([step])
      assert first.rendered["payload"] == %{"user" => "alice"}
      assert second.rendered["payload"] == %{"user" => "bob"}
    end

    test "sibling steps sharing a rows dataset iterate independently, not interleaved" do
      shared_rows = %{rows: [%{"n" => 1}, %{"n" => 2}]}

      step_a =
        template_step(name: "A", payload: %{"n" => "{{n}}", "step" => "a"}, dataset: shared_rows)

      step_b =
        template_step(name: "B", payload: %{"n" => "{{n}}", "step" => "b"}, dataset: shared_rows)

      assert {:ok, {results, _saved}} = Step.run_steps([step_a, step_b])

      assert Enum.map(results, & &1.rendered["payload"]) == [
               %{"n" => 1, "step" => "a"},
               %{"n" => 2, "step" => "a"},
               %{"n" => 1, "step" => "b"},
               %{"n" => 2, "step" => "b"}
             ]
    end
  end

  describe "run_steps/2 save state threading" do
    test "a later step's dataset can reference an earlier step's saved value" do
      step1 =
        template_step(
          payload: %{"seed" => "{{seed}}"},
          dataset: %{data: %{"seed" => "abc"}},
          save: [%{path: "$.echo.payload.seed", as: "auth_token"}]
        )

      step2 =
        template_step(
          payload: %{"authorization" => "Bearer {{auth_token}}"},
          dataset: %{data: %{}}
        )

      assert {:ok, {[_first, second], saved}} = Step.run_steps([step1, step2])
      assert saved["auth_token"] == "abc"
      assert second.rendered["payload"] == %{"authorization" => "Bearer abc"}
    end

    test "save state threads across a single step's own row executions" do
      step1 =
        template_step(
          payload: %{"marker" => "{{marker}}"},
          dataset: %{rows: [%{"marker" => "row1"}, %{"marker" => "row2"}]},
          save: [%{path: "$.echo.payload.marker", as: "last_marker"}]
        )

      assert {:ok, {_results, saved}} = Step.run_steps([step1])
      assert saved["last_marker"] == "row2"
    end

    test "a save entry whose path doesn't resolve is silently skipped" do
      step =
        template_step(
          payload: %{"foo" => "bar"},
          dataset: %{data: %{}},
          save: [%{path: "$.echo.payload.nonexistent", as: "missing_value"}]
        )

      assert {:ok, {[result], saved}} = Step.run_steps([step])
      assert result.status == :ok
      refute Map.has_key?(saved, "missing_value")
    end

    test "saved values win over dataset fields on collision" do
      step1 =
        template_step(
          payload: %{"v" => "seed"},
          dataset: %{data: %{}},
          save: [%{path: "$.echo.payload.v", as: "shared"}]
        )

      step2 =
        template_step(
          payload: %{"v" => "{{shared}}"},
          dataset: %{data: %{"shared" => "dataset-value"}}
        )

      assert {:ok, {[_first, second], _saved}} = Step.run_steps([step1, step2])
      assert second.rendered["payload"] == %{"v" => "seed"}
    end
  end

  describe "run_steps/2 failure handling" do
    test "a missing interpolation key fails the step but not the sequence" do
      failing = template_step(payload: %{"x" => "{{missing}}"}, dataset: %{data: %{}})
      ok_step = template_step(payload: %{"ok" => true}, dataset: %{data: %{}})

      assert {:error, {[first, second], _saved}} = Step.run_steps([failing, ok_step])
      assert first.status == :error

      assert first.response == %ClientError{
               stage: :interpolation,
               reason: :payload_render_failed,
               details: {:missing_interpolation_key, "missing"}
             }

      assert second.status == :ok
    end

    test "an unregistered client fails the step but not the sequence" do
      failing = template_step(client: "does_not_exist", payload: %{}, dataset: %{data: %{}})
      ok_step = template_step(payload: %{"ok" => true}, dataset: %{data: %{}})

      assert {:error, {[first, second], _saved}} = Step.run_steps([failing, ok_step])
      assert first.status == :error

      assert %ClientError{stage: :client_lookup, reason: :client_not_found, details: :not_found} =
               first.response

      assert second.status == :ok
    end

    test "returns :ok when every step in a multi-step run succeeds" do
      step1 = template_step(payload: %{"a" => 1}, dataset: %{data: %{}})
      step2 = template_step(payload: %{"b" => 2}, dataset: %{data: %{}})

      assert {:ok, {[_first, _second], _saved}} = Step.run_steps([step1, step2])
    end

    test "a failure inside a nested scenario call propagates to the outer :error" do
      failing_leaf = template_step(client: "does_not_exist", payload: %{}, dataset: %{data: %{}})
      scenario_step = %{scenario: %{steps: [failing_leaf]}}
      after_step = template_step(payload: %{"ok" => true}, dataset: %{data: %{}})

      assert {:error, {[nested_result, after_result], _saved}} =
               Step.run_steps([scenario_step, after_step])

      assert nested_result.status == :error
      assert after_result.status == :ok
    end

    test "a client raising is rescued into a structured error, not a crash" do
      failing =
        template_step(client: "test_client_crashing", payload: %{}, dataset: %{data: %{}})

      ok_step = template_step(payload: %{"ok" => true}, dataset: %{data: %{}})

      assert {:error, {[first, second], _saved}} = Step.run_steps([failing, ok_step])
      assert first.status == :error

      assert %ClientError{stage: :send, reason: :client_raised, details: "client boom"} =
               first.response

      assert second.status == :ok
    end
  end

  describe "run_steps/2 scenario recursion" do
    test "recurses into a scenario call's nested steps" do
      scenario_step = %{
        scenario: %{
          steps: [
            template_step(payload: %{"nested" => true}, dataset: %{data: %{}})
          ]
        }
      }

      assert {:ok, {[result], _saved}} = Step.run_steps([scenario_step])
      assert result.rendered["payload"] == %{"nested" => true}
    end

    test "save state threads out of a scenario call to later sibling steps" do
      scenario_step = %{
        scenario: %{
          steps: [
            template_step(
              payload: %{"seed" => "from-scenario"},
              dataset: %{data: %{}},
              save: [%{path: "$.echo.payload.seed", as: "token"}]
            )
          ]
        }
      }

      after_step = template_step(payload: %{"v" => "{{token}}"}, dataset: %{data: %{}})

      assert {:ok, {[_scenario_result, after_result], saved}} =
               Step.run_steps([scenario_step, after_step])

      assert saved["token"] == "from-scenario"
      assert after_result.rendered["payload"] == %{"v" => "from-scenario"}
    end
  end

  describe "run_steps/2 assertions" do
    test "all assertions passing keeps the step :ok" do
      step =
        template_step(
          payload: %{"ok" => true},
          dataset: %{data: %{}},
          assert: [%{matcher: "test_matcher", expected: nil}]
        )

      assert {:ok, {[result], _saved}} = Step.run_steps([step])
      assert result.status == :ok

      assert [%{status: :ok, reasons: [], assertion: %{matcher: "test_matcher"}}] =
               result.assertions
    end

    test "a failing assertion flips a successful dispatch to :error" do
      step =
        template_step(
          payload: %{"ok" => true},
          dataset: %{data: %{}},
          assert: [%{"should_fail" => true, matcher: "test_matcher", expected: nil}]
        )

      assert {:error, {[result], _saved}} = Step.run_steps([step])
      assert result.status == :error
      assert result.response == %{"echo" => result.rendered}

      assert [%{status: :error, reasons: [reason], assertion: %{matcher: "test_matcher"}}] =
               result.assertions

      assert %Maestro.Assert.Reason{reason: :test_matcher_saw} = reason
    end

    test "json_match works end-to-end against the real response" do
      step =
        template_step(
          payload: %{"ok" => true},
          dataset: %{data: %{}},
          assert: [%{matcher: "json_match", path: "$.echo.payload.ok", expected: true}]
        )

      assert {:ok, {[result], _saved}} = Step.run_steps([step])
      assert result.status == :ok
    end

    test "multiple assertions with one failing are all recorded, aggregate :error" do
      step =
        template_step(
          payload: %{"ok" => true},
          dataset: %{data: %{}},
          assert: [
            %{matcher: "test_matcher_always_ok", expected: nil},
            %{"should_fail" => true, matcher: "test_matcher", expected: nil}
          ]
        )

      assert {:error, {[result], _saved}} = Step.run_steps([step])
      assert result.status == :error

      assert [
               %{status: :ok, reasons: [], assertion: %{matcher: "test_matcher_always_ok"}},
               %{status: :error, reasons: [_reason], assertion: %{matcher: "test_matcher"}}
             ] = result.assertions
    end

    test "a step without assert entries has empty assertions and stays :ok" do
      step = template_step(payload: %{"ok" => true}, dataset: %{data: %{}})

      assert {:ok, {[result], _saved}} = Step.run_steps([step])
      assert result.assertions == []
    end

    test "a dispatch failure means assertions never run" do
      step =
        template_step(
          client: "does_not_exist",
          payload: %{},
          dataset: %{data: %{}},
          assert: [%{matcher: "test_matcher", expected: nil}]
        )

      assert {:error, {[result], _saved}} = Step.run_steps([step])
      assert result.status == :error
      assert result.assertions == []
    end

    test "save extraction still happens alongside a failed assertion" do
      step =
        template_step(
          payload: %{"seed" => "abc"},
          dataset: %{data: %{}},
          save: [%{path: "$.echo.payload.seed", as: "token"}],
          assert: [%{"should_fail" => true, matcher: "test_matcher", expected: nil}]
        )

      assert {:error, {[result], saved}} = Step.run_steps([step])
      assert result.status == :error
      assert saved["token"] == "abc"
    end

    test "an unregistered matcher name surfaces as an assertion-level :not_found reason" do
      step =
        template_step(
          payload: %{},
          dataset: %{data: %{}},
          assert: [%{matcher: "does_not_exist", expected: 1}]
        )

      assert {:error, {[result], _saved}} = Step.run_steps([step])

      assert [
               %{
                 status: :error,
                 reasons: [%Maestro.Assert.Reason{reason: :matcher_not_found}],
                 assertion: %{matcher: "does_not_exist"}
               }
             ] = result.assertions
    end

    test "a template-step nested inside a scenario call still runs its own assert" do
      leaf =
        template_step(
          payload: %{"ok" => true},
          dataset: %{data: %{}},
          assert: [%{"should_fail" => true, matcher: "test_matcher", expected: nil}]
        )

      scenario_step = %{scenario: %{steps: [leaf]}}

      assert {:error, {[result], _saved}} = Step.run_steps([scenario_step])
      assert result.status == :error
      assert [%{status: :error, assertion: %{matcher: "test_matcher"}}] = result.assertions
    end
  end

  describe "run_steps/2 default step naming" do
    test "falls back to \"<client>: <template name>\" when the step has no name" do
      step = %{
        client: "test_client_no_optional",
        template: %{name: "my_template", payload: %{}, options: %{}},
        dataset: %{data: %{}}
      }

      assert {:ok, {[result], _saved}} = Step.run_steps([step])
      assert result.name == "test_client_no_optional: my_template"
    end

    test "falls back to \"unnamed\" when neither the step nor the template has a name" do
      step = %{
        client: "test_client_no_optional",
        template: %{payload: %{}, options: %{}},
        dataset: %{data: %{}}
      }

      assert {:ok, {[result], _saved}} = Step.run_steps([step])
      assert result.name == "test_client_no_optional: unnamed"
    end

    test "a scenario call is transparent the nested step's own name is what appears" do
      leaf = Map.put(ok_leaf(), :name, "the leaf step")
      scenario_step = %{scenario: %{name: "login", steps: [leaf]}}

      assert {:ok, {[result], _saved}} = Step.run_steps([scenario_step])
      assert result.name == "the leaf step"
    end
  end

  defp ok_leaf, do: template_step(payload: %{}, dataset: %{data: %{}})
end
