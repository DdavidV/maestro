defmodule Maestro.Report.JUnitTest do
  use ExUnit.Case, async: true

  require Record

  alias Maestro.Assert.AssertionResult
  alias Maestro.Assert.Reason
  alias Maestro.Client
  alias Maestro.Report.JUnit
  alias Maestro.Report.Model

  Record.defrecordp(
    :xml_element,
    :xmlElement,
    Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(
    :xml_attribute,
    :xmlAttribute,
    Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(
    :xml_text,
    :xmlText,
    Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl")
  )

  defp step(overrides \\ %{}) do
    Map.merge(
      %{
        name: "step",
        status: :ok,
        client: "http",
        rendered: %{"payload" => %{}, "options" => %{}},
        response: %{"ok" => true},
        assertions: [],
        duration: 1_000
      },
      overrides
    )
  end

  defp testcase(overrides \\ %{}) do
    Map.merge(%{id: "tc1", status: :ok, steps: [step()], duration: 2_000}, overrides)
  end

  defp suite(overrides \\ %{}) do
    Map.merge(%{id: "suite1", status: :ok, testcases: [testcase()], duration: 3_000}, overrides)
  end

  defp run_result(overrides) do
    Map.merge(%{run_id: "run_1", status: :ok, suites: [suite()]}, overrides)
  end

  defp failed_assertion do
    %AssertionResult{
      status: :error,
      assertion: %{matcher: "json_match", expected: "confirmed", path: "$.status"},
      actual: %{"status" => "pending"},
      reasons: [Reason.new(:not_equal, "confirmed", "pending", "$.status")]
    }
  end

  defp failing_testcase(id) do
    testcase(%{
      id: id,
      status: :error,
      steps: [step(%{name: "check status", status: :error, assertions: [failed_assertion()]})]
    })
  end

  defp erroring_testcase(id) do
    error = Client.Error.new(:client_lookup, :client_not_found, :not_found)

    testcase(%{
      id: id,
      status: :error,
      steps: [step(%{name: "call it", status: :error, response: error})]
    })
  end

  defp render(run_result), do: run_result |> Model.build() |> JUnit.render()

  defp parse(xml) do
    {doc, []} = :xmerl_scan.string(:binary.bin_to_list(xml), quiet: true)
    doc
  end

  defp xpath(doc, path), do: :xmerl_xpath.string(String.to_charlist(path), doc)

  defp attr(doc, path) do
    case xpath(doc, path) do
      [xml_attribute(value: value)] -> List.to_string(value)
      [] -> nil
    end
  end

  defp text(doc, path) do
    doc
    |> xpath(path)
    |> Enum.flat_map(fn xml_element(content: content) -> content end)
    |> Enum.map_join(fn xml_text(value: value) -> List.to_string(value) end)
  end

  defp count(doc, path), do: length(xpath(doc, path))

  test "format metadata" do
    assert JUnit.name() == "junit"
    assert JUnit.extension() == "xml"
    assert JUnit.content_type() == "application/xml"
  end

  test "renders a well-formed document with the XML declaration" do
    xml = render(run_result(%{}))

    assert String.starts_with?(xml, ~s(<?xml version="1.0" encoding="UTF-8"?>))
    assert xml_element(name: :testsuites) = parse(xml)
  end

  test "maps suites to testsuite and testcases to testcase, classname = suite id" do
    doc =
      render(
        run_result(%{
          suites: [
            suite(%{id: "checkout", testcases: [testcase(%{id: "add"}), testcase(%{id: "pay"})]}),
            suite(%{id: "health", testcases: [testcase(%{id: "ping"})]})
          ]
        })
      )
      |> parse()

    assert attr(doc, "/testsuites/@name") == "Maestro run_1"
    assert count(doc, "/testsuites/testsuite") == 2
    assert attr(doc, "/testsuites/testsuite[1]/@name") == "checkout"
    assert attr(doc, "/testsuites/testsuite[1]/@tests") == "2"
    assert attr(doc, "/testsuites/testsuite[1]/testcase[2]/@name") == "pay"
    assert attr(doc, "/testsuites/testsuite[1]/testcase[2]/@classname") == "checkout"
    assert attr(doc, "/testsuites/@tests") == "3"
  end

  test "a passing testcase has no failure/error, but logs its steps in system-out" do
    doc = render(run_result(%{})) |> parse()

    assert count(doc, "//testcase/failure") == 0
    assert count(doc, "//testcase/error") == 0
    assert text(doc, "//testcase/system-out") =~ "[OK   ] 1. step (http) — 1.0 ms"
    assert text(doc, "//testcase/system-out") =~ "(no assertions)"
  end

  test "an assertion mismatch becomes a <failure> with type, message and details" do
    doc = render(run_result(%{suites: [suite(%{testcases: [failing_testcase("t")]})]})) |> parse()

    assert attr(doc, "//testcase/failure/@type") == "not_equal"

    assert attr(doc, "//testcase/failure/@message") ==
             ~s(step "check status": json_match not_equal at $.status)

    body = text(doc, "//testcase/failure")
    assert body =~ "reason: not_equal"
    assert body =~ ~s(expected: "confirmed")
    assert body =~ ~s(actual: "pending")
    assert attr(doc, "/testsuites/@failures") == "1"
    assert attr(doc, "/testsuites/@errors") == "0"
  end

  test "a dispatch error becomes an <error>, counted separately from failures" do
    doc =
      render(
        run_result(%{
          suites: [suite(%{testcases: [erroring_testcase("e"), failing_testcase("f")]})]
        })
      )
      |> parse()

    assert attr(doc, "//testcase[@name='e']/error/@type") == "client_not_found"
    assert attr(doc, "//testcase[@name='e']/error/@message") =~ "stage: client_lookup"
    assert text(doc, "//testcase[@name='e']/error") =~ "details: :not_found"
    assert count(doc, "//testcase[@name='e']/failure") == 0
    assert attr(doc, "/testsuites/testsuite/@failures") == "1"
    assert attr(doc, "/testsuites/testsuite/@errors") == "1"
  end

  test "an unfinished suite is reported with a skipped placeholder testcase" do
    doc =
      render(
        run_result(%{
          status: :running,
          suites: [suite(), suite(%{id: "later", status: :pending, testcases: [], duration: nil})]
        })
      )
      |> parse()

    assert attr(doc, "//testsuite[@name='later']/@tests") == "1"
    assert attr(doc, "//testsuite[@name='later']/@skipped") == "1"
    assert attr(doc, "//testsuite[@name='later']/testcase/@name") == "(not finished)"
    assert attr(doc, "//testsuite[@name='later']/testcase/skipped/@message") =~ "pending"

    assert attr(doc, "//testsuite[@name='later']/properties/property/@value") == "pending"
    assert attr(doc, "/testsuites/@skipped") == "1"
  end

  test "time attributes are seconds derived from microsecond durations" do
    doc = render(run_result(%{suites: [suite(%{duration: 1_234_567})]})) |> parse()

    assert attr(doc, "/testsuites/@time") == "1.235"
    assert attr(doc, "/testsuites/testsuite/@time") == "1.235"
    assert attr(doc, "//testcase/@time") == "0.002"
  end

  test "markup and control characters in ids/names can't break the document" do
    hostile = ~s(<tag attr="x"> & 'quotes'\u0001\nnewline)

    doc =
      render(
        run_result(%{
          suites: [
            suite(%{
              id: hostile,
              testcases: [
                testcase(%{
                  id: hostile,
                  status: :error,
                  steps: [
                    step(%{name: hostile, status: :error, assertions: [failed_assertion()]})
                  ]
                })
              ]
            })
          ]
        })
      )
      |> parse()

    expected = String.replace(hostile, "\u0001", "")
    assert attr(doc, "/testsuites/testsuite/@name") == expected
    assert attr(doc, "//testcase/@name") == expected
    assert text(doc, "//testcase/failure") =~ "<tag attr=\"x\">"
  end
end
