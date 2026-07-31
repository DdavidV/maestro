defmodule Maestro.Report.DefaultLayoutTest do
  use ExUnit.Case, async: true

  alias Maestro.Assert.AssertionResult
  alias Maestro.Assert.Reason
  alias Maestro.Client
  alias Maestro.Report.DefaultLayout
  alias Maestro.Report.Model

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

  defp render(run_result), do: run_result |> Model.build() |> DefaultLayout.render()

  describe "render/1" do
    test "starts with the doctype and contains the run_id" do
      html = render(run_result(%{run_id: "run_abc123"}))

      assert String.starts_with?(html, "<!DOCTYPE html>")
      assert html =~ "run_abc123"
    end

    test "every suite id appears in both the top-level TOC and its own section" do
      html =
        render(
          run_result(%{
            suites: [
              suite(%{id: "checkout", testcases: [testcase(%{id: "add_to_cart"})]}),
              suite(%{id: "healthcheck", testcases: [testcase(%{id: "ping"})]})
            ]
          })
        )

      for id <- ["checkout", "healthcheck"] do
        occurrences = html |> String.split(id) |> length()

        assert occurrences >= 3,
               "expected #{id} to appear at least twice (top-level TOC + section), got #{occurrences - 1} occurrences"
      end
    end

    test "each suite has its own per-suite TOC listing only its own testcases" do
      html =
        render(
          run_result(%{
            suites: [
              suite(%{
                id: "checkout",
                anchor: "suite-checkout",
                testcases: [testcase(%{id: "add_to_cart"})]
              }),
              suite(%{
                id: "healthcheck",
                anchor: "suite-healthcheck",
                testcases: [testcase(%{id: "ping"})]
              })
            ]
          })
        )

      [_before_checkout, after_checkout] = String.split(html, "id=\"suite-checkout\"", parts: 2)

      [checkout_section, healthcheck_section] =
        String.split(after_checkout, "id=\"suite-healthcheck\"", parts: 2)

      assert checkout_section =~ "add_to_cart"
      refute checkout_section =~ "ping"
      assert healthcheck_section =~ "ping"
    end

    test "each suite section carries the page-break class for print/PDF pagination" do
      html =
        render(
          run_result(%{
            suites: [suite(%{id: "s1"}), suite(%{id: "s2"})]
          })
        )

      occurrences = Regex.scan(~r/class="m-suite m-page"/, html) |> length()
      assert occurrences == 2
    end

    test "every TOC href has a matching id elsewhere in the document" do
      html =
        render(
          run_result(%{
            suites: [
              suite(%{id: "s1", testcases: [testcase(%{id: "tc1"}), testcase(%{id: "tc2"})]})
            ]
          })
        )

      hrefs = Regex.scan(~r/href="#([a-z0-9_-]+)"/, html) |> Enum.map(&Enum.at(&1, 1))
      ids = Regex.scan(~r/id="([a-z0-9_-]+)"/, html) |> Enum.map(&Enum.at(&1, 1))

      assert hrefs != []
      assert Enum.all?(hrefs, &(&1 in ids))
    end

    test "a step with no assertions renders the no-assertions marker" do
      html =
        render(
          run_result(%{
            suites: [suite(%{testcases: [testcase(%{steps: [step(%{assertions: []})]})]})]
          })
        )

      assert html =~ "(no assertions)"
    end

    test "a failed assertion with multiple Reason entries renders every entry" do
      assertion = %AssertionResult{
        status: :error,
        assertion: %{matcher: "json_match", expected: %{"a" => 1}},
        actual: %{"a" => 9},
        reasons: [
          Reason.new(:not_equal, 1, 9, ".a"),
          Reason.new(:not_equal, 2, 9, ".b")
        ]
      }

      html =
        render(
          run_result(%{
            suites: [
              suite(%{
                status: :error,
                testcases: [
                  testcase(%{
                    status: :error,
                    steps: [step(%{status: :error, assertions: [assertion]})]
                  })
                ]
              })
            ]
          })
        )

      assert html =~ "path: .a"
      assert html =~ "path: .b"
      assert (html |> String.split("reason: not_equal") |> length()) - 1 == 2
    end

    test "a passing assertion still renders its expected and actual values" do
      assertion = %AssertionResult{
        status: :ok,
        assertion: %{matcher: "json_match", expected: %{"a" => 1}},
        actual: %{"a" => 1},
        reasons: []
      }

      html =
        render(
          run_result(%{
            suites: [
              suite(%{
                testcases: [testcase(%{steps: [step(%{assertions: [assertion]})]})]
              })
            ]
          })
        )

      assert html =~ "expected: %{&quot;a&quot; =&gt; 1}"
      assert html =~ "actual: %{&quot;a&quot; =&gt; 1}"
    end

    test "a passing assertion with a path shows the path alongside expected/actual" do
      assertion = %AssertionResult{
        status: :ok,
        assertion: %{matcher: "json_match", expected: "ok", path: "$.echo.payload.status"},
        actual: %{"echo" => %{"payload" => %{"status" => "ok"}}},
        reasons: []
      }

      html =
        render(
          run_result(%{
            suites: [
              suite(%{
                testcases: [testcase(%{steps: [step(%{assertions: [assertion]})]})]
              })
            ]
          })
        )

      assert html =~ "path: $.echo.payload.status"
      assert html =~ "expected: &quot;ok&quot;"
    end

    test "a dispatch-error step renders stage/reason/details" do
      error = Client.Error.new(:client_lookup, :client_not_found, :not_found)

      html =
        render(
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
        )

      assert html =~ "stage: client_lookup"
      assert html =~ "reason: client_not_found"
      assert html =~ "details: :not_found"
    end

    test "summary counts appear in the header" do
      html =
        render(
          run_result(%{
            suites: [
              suite(%{id: "s1", status: :ok}),
              suite(%{id: "s2", status: :error})
            ]
          })
        )

      assert html =~ "Total suites: 2"
      assert html =~ "Passed: 1"
      assert html =~ "Failed: 1"
    end
  end
end
