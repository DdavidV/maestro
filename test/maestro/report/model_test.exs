defmodule Maestro.Report.ModelTest do
  use ExUnit.Case, async: true

  alias Maestro.Assert.AssertionResult
  alias Maestro.Assert.Reason
  alias Maestro.Client
  alias Maestro.Report.Model

  defp ok_assertion(matcher \\ "test_matcher") do
    %AssertionResult{
      status: :ok,
      assertion: %{matcher: matcher, expected: 1},
      actual: 1,
      reasons: []
    }
  end

  defp failing_assertion(reasons) do
    %AssertionResult{
      status: :error,
      assertion: %{matcher: "json_match", expected: %{"a" => 1}},
      actual: %{"a" => 9},
      reasons: reasons
    }
  end

  defp step(overrides \\ %{}) do
    Map.merge(
      %{
        name: "step",
        status: :ok,
        client: "http",
        rendered: %{"payload" => %{}, "options" => %{}},
        response: %{"ok" => true},
        assertions: []
      },
      overrides
    )
  end

  defp testcase(overrides \\ %{}) do
    Map.merge(%{id: "tc1", status: :ok, steps: [step()]}, overrides)
  end

  defp suite(overrides \\ %{}) do
    Map.merge(%{id: "suite1", status: :ok, testcases: [testcase()]}, overrides)
  end

  defp run_result(overrides) do
    Map.merge(%{run_id: "run_1", status: :ok, suites: [suite()]}, overrides)
  end

  describe "build/1" do
    test "every suite/testcase/step is preserved in order" do
      run_result =
        run_result(%{
          suites: [
            suite(%{id: "s1", testcases: [testcase(%{id: "tc1"}), testcase(%{id: "tc2"})]}),
            suite(%{id: "s2", testcases: [testcase(%{id: "tc3"})]})
          ]
        })

      model = Model.build(run_result)

      assert Enum.map(model.suites, & &1.id) == ["s1", "s2"]
      assert Enum.map(Enum.at(model.suites, 0).testcases, & &1.id) == ["tc1", "tc2"]
      assert Enum.map(Enum.at(model.suites, 1).testcases, & &1.id) == ["tc3"]
    end

    test "a step with assertions: [] still appears, with assertions: []" do
      run_result =
        run_result(%{
          suites: [suite(%{testcases: [testcase(%{steps: [step(%{assertions: []})]})]})]
        })

      model = Model.build(run_result)
      [step_model] = Enum.at(model.suites, 0).testcases |> Enum.at(0) |> Map.fetch!(:steps)

      assert step_model.assertions == []
      assert step_model.dispatch_error == nil
    end

    test "an assertion with multiple Reason entries produces the same number of failure_rows" do
      reasons = [
        Reason.new(:not_equal, 1, 9, ".a"),
        Reason.new(:not_equal, 2, 9, ".b")
      ]

      run_result =
        run_result(%{
          suites: [
            suite(%{
              status: :error,
              testcases: [
                testcase(%{
                  status: :error,
                  steps: [
                    step(%{status: :error, assertions: [failing_assertion(reasons)]})
                  ]
                })
              ]
            })
          ]
        })

      model = Model.build(run_result)
      [step_model] = Enum.at(model.suites, 0).testcases |> Enum.at(0) |> Map.fetch!(:steps)
      [assertion_model] = step_model.assertions

      assert length(assertion_model.failures) == 2

      assert Enum.map(assertion_model.failures, & &1.path) == [".a", ".b"]
      assert Enum.all?(assertion_model.failures, &(&1.kind == :assertion_mismatch))
      assert Enum.map(assertion_model.failures, & &1.reason) == [:not_equal, :not_equal]
      assert Enum.map(assertion_model.failures, & &1.expected) == [1, 2]
      assert Enum.map(assertion_model.failures, & &1.actual) == [9, 9]
    end

    test "a passing assertion has an empty failures list" do
      run_result =
        run_result(%{
          suites: [
            suite(%{testcases: [testcase(%{steps: [step(%{assertions: [ok_assertion()]})]})]})
          ]
        })

      model = Model.build(run_result)
      [step_model] = Enum.at(model.suites, 0).testcases |> Enum.at(0) |> Map.fetch!(:steps)
      [assertion_model] = step_model.assertions

      assert assertion_model.status == :ok
      assert assertion_model.failures == []
    end

    test "a step whose response is a Client.Error produces dispatch_error and empty assertions" do
      error = Client.Error.new(:client_lookup, :client_not_found, :not_found)

      run_result =
        run_result(%{
          suites: [
            suite(%{
              status: :error,
              testcases: [
                testcase(%{
                  status: :error,
                  steps: [step(%{status: :error, response: error, assertions: []})]
                })
              ]
            })
          ]
        })

      model = Model.build(run_result)
      [step_model] = Enum.at(model.suites, 0).testcases |> Enum.at(0) |> Map.fetch!(:steps)

      assert step_model.assertions == []

      assert step_model.dispatch_error == %{
               kind: :dispatch_error,
               reason: :client_not_found,
               expected: nil,
               actual: nil,
               path: nil,
               stage: :client_lookup,
               details: :not_found
             }
    end

    test "summary counts match suite statuses" do
      run_result =
        run_result(%{
          suites: [
            suite(%{id: "s1", status: :ok}),
            suite(%{id: "s2", status: :error}),
            suite(%{id: "s3", status: :ok})
          ]
        })

      model = Model.build(run_result)
      assert model.summary == %{total: 3, ok: 2, error: 1}
    end

    test "anchors are unique and HTML-id-safe for ids with spaces/punctuation" do
      run_result =
        run_result(%{
          suites: [
            suite(%{id: "Checkout Flow! v2", testcases: [testcase(%{id: "Add To Cart?"})]})
          ]
        })

      model = Model.build(run_result)
      suite_model = Enum.at(model.suites, 0)
      testcase_model = Enum.at(suite_model.testcases, 0)

      assert suite_model.anchor =~ ~r/^[a-z0-9_-]+$/
      assert testcase_model.anchor =~ ~r/^[a-z0-9_-]+$/
      assert suite_model.anchor != testcase_model.anchor
    end

    test "builds without raising against a :running/partial run_result" do
      run_result =
        run_result(%{
          status: :running,
          suites: [
            suite(%{status: :ok}),
            suite(%{id: "s2", status: :running, testcases: []}),
            %{id: "s3", status: :pending, testcases: []}
          ]
        })

      model = Model.build(run_result)

      assert model.status == :running
      assert Enum.map(model.suites, & &1.status) == [:ok, :running, :pending]
      assert Enum.at(model.suites, 2).testcases == []
    end

    test "run_id/status/generated_at are set correctly" do
      model = Model.build(run_result(%{run_id: "run_abc", status: :ok}))

      assert model.run_id == "run_abc"
      assert model.status == :ok
      assert %DateTime{} = model.generated_at
    end
  end
end
