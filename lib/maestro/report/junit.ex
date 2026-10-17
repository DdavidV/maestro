defmodule Maestro.Report.JUnit do
  @moduledoc """
  A `Maestro.Report.Format` rendering a run as JUnit XML, the de facto test
  result interchange format CI systems (GitLab, GitHub Actions reporters,
  Jenkins, Azure DevOps, CircleCI, Buildkite, ...) read to show per-test
  results, history and timings.

  Enable it alongside the HTML report with:

      config :maestro, :report_formats, [Maestro.Report.DefaultLayout, Maestro.Report.JUnit]

  It can also be fetched on demand without being configured, e.g.
  `GET /api/runs/{run_id}/report?format=junit`.

  ## Mapping

    * the run is the root `<testsuites>` element (`name="Maestro <run_id>"`),
      carrying the totals across every suite.
    * each suite is a `<testsuite name="<suite id>">`.
    * each testcase is a `<testcase name="<testcase id>" classname="<suite id>">`.
    * a failing testcase gets exactly one child: `<error>` if any of its
      steps failed to dispatch (`Maestro.Client.Error`: interpolation,
      client lookup, `init/2`/`send/2`), else `<failure>` (its steps ran
      but an assertion didn't hold) the same "couldn't run" vs. "ran but
      wrong" distinction JUnit itself draws. `message`/`type` describe the
      first problem; the body lists every failing step's details.
    * every testcase, passing or not, gets a `<system-out>` listing each of
      its steps with status, client, duration and assertions, so nothing a
      run did is hidden from a CI's test view.
    * a suite still `:pending`/`:running` when the report is rendered (a
      partial report, or a crashed run) gets an extra
      `<testcase name="(not finished)">` marked `<skipped>`, so it shows up
      in CI as skipped rather than silently having fewer tests.
    * `time` attributes are seconds (3 decimals), from the run's
      microsecond `duration`s.

  JUnit has no nesting below `<testcase>`, so steps and assertions live in
  the text of `<failure>`/`<error>`/`<system-out>` rather than as elements.
  """

  @behaviour Maestro.Report.Format

  alias Maestro.Report.Model

  @not_finished "(not finished)"

  @impl true
  def name, do: "junit"

  @impl true
  def extension, do: "xml"

  @impl true
  def content_type, do: "application/xml"

  @impl true
  @spec render(Model.t()) :: String.t()
  def render(model) do
    suites = Enum.map(model.suites, &suite_counts/1)
    totals = Enum.reduce(suites, %{tests: 0, failures: 0, errors: 0, skipped: 0}, &add_counts/2)

    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      element(
        "testsuites",
        [
          name: "Maestro #{model.run_id}",
          tests: totals.tests,
          failures: totals.failures,
          errors: totals.errors,
          skipped: totals.skipped,
          time: seconds(model.summary.duration)
        ],
        Enum.map(suites, &testsuite/1)
      )
    ]
    |> IO.iodata_to_binary()
  end

  defp suite_counts(suite) do
    testcases = Enum.map(suite.testcases, &{&1, classify(&1)})
    unfinished? = suite.status in [:pending, :running]

    counts = %{
      tests: length(testcases) + if(unfinished?, do: 1, else: 0),
      failures: Enum.count(testcases, &match?({_, :failure}, &1)),
      errors: Enum.count(testcases, &match?({_, :error}, &1)),
      skipped: if(unfinished?, do: 1, else: 0)
    }

    {suite, testcases, unfinished?, counts}
  end

  defp add_counts({_suite, _testcases, _unfinished?, counts}, acc) do
    Map.merge(acc, counts, fn _key, a, b -> a + b end)
  end

  defp testsuite({suite, testcases, unfinished?, counts}) do
    children = [
      if(unfinished?, do: properties(suite), else: []),
      Enum.map(testcases, fn {testcase, kind} -> testcase(suite, testcase, kind) end),
      if(unfinished?, do: not_finished(suite), else: [])
    ]

    element(
      "testsuite",
      [
        name: suite.id,
        tests: counts.tests,
        failures: counts.failures,
        errors: counts.errors,
        skipped: counts.skipped,
        time: seconds(suite.duration)
      ],
      children
    )
  end

  defp properties(suite) do
    element("properties", [], [
      element("property", [name: "maestro.suite_status", value: suite.status], nil)
    ])
  end

  defp not_finished(suite) do
    element("testcase", [name: @not_finished, classname: suite.id, time: seconds(nil)], [
      element(
        "skipped",
        [message: "Suite was still #{suite.status} when this report was generated."],
        nil
      )
    ])
  end

  defp testcase(suite, testcase, kind) do
    element(
      "testcase",
      [name: testcase.id, classname: suite.id, time: seconds(testcase.duration)],
      [problem(testcase, kind), element("system-out", [], text(step_log(testcase.steps)))]
    )
  end

  # `:ok` testcases have no problem element; otherwise `:error` wins over
  # `:failure` if any step failed to dispatch at all.
  defp classify(%{status: :ok}), do: :ok

  defp classify(testcase) do
    if Enum.any?(testcase.steps, & &1.dispatch_error), do: :error, else: :failure
  end

  defp problem(_testcase, :ok), do: []

  defp problem(testcase, kind) do
    failing = Enum.filter(testcase.steps, &(&1.status == :error))
    {type, message} = summarize(List.first(failing))

    element(
      Atom.to_string(kind),
      [message: message, type: type],
      text(Enum.map_join(failing, "\n", &step_details/1))
    )
  end

  defp summarize(nil), do: {"error", "testcase failed"}

  defp summarize(%{dispatch_error: %{} = error} = step) do
    {error.reason, ~s(step "#{step.name}": #{error.reason} \(stage: #{error.stage}\))}
  end

  defp summarize(step) do
    case Enum.find(step.assertions, &(&1.status == :error)) do
      %{failures: [failure | _]} = assertion ->
        at = if failure.path, do: " at #{failure.path}", else: ""
        {failure.reason, ~s(step "#{step.name}": #{assertion.matcher} #{failure.reason}#{at})}

      %{} = assertion ->
        {"assertion_failed", ~s(step "#{step.name}": #{assertion.matcher} failed)}

      nil ->
        {"step_failed", ~s(step "#{step.name}" failed)}
    end
  end

  defp step_details(step) do
    header = ~s(step "#{step.name}"#{client(step)})

    lines =
      if step.dispatch_error do
        failure_lines(step.dispatch_error)
      else
        step.assertions
        |> Enum.filter(&(&1.status == :error))
        |> Enum.flat_map(fn assertion ->
          failures = Enum.flat_map(assertion.failures, &failure_lines/1)
          ["#{assertion.matcher}:" | Enum.map(failures, &("  " <> &1))]
        end)
      end

    Enum.join([header | Enum.map(lines, &("  " <> &1))], "\n")
  end

  defp failure_lines(failure) do
    [
      failure.stage && "stage: #{failure.stage}",
      "reason: #{failure.reason}",
      failure.path && "path: #{failure.path}",
      failure.kind == :assertion_mismatch && "expected: #{inspect(failure.expected)}",
      failure.kind == :assertion_mismatch && "actual: #{inspect(failure.actual)}",
      failure.kind == :dispatch_error && "details: #{inspect(failure.details)}"
    ]
    |> Enum.filter(&is_binary/1)
  end

  defp step_log(steps) do
    steps
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {step, index} ->
      duration = Maestro.Util.format_duration(step.duration)
      status = step.status |> Atom.to_string() |> String.upcase() |> String.pad_trailing(5)
      header = ~s([#{status}] #{index}. #{step.name}#{client(step)} — #{duration})

      details =
        cond do
          step.dispatch_error ->
            Enum.map(failure_lines(step.dispatch_error), &("    " <> &1))

          step.assertions == [] ->
            ["    (no assertions)"]

          true ->
            Enum.map(step.assertions, fn assertion ->
              path = if assertion.path, do: " @ #{assertion.path}", else: ""
              "    #{assertion.matcher}#{path}: #{assertion.status}"
            end)
        end

      Enum.join([header | details], "\n")
    end)
  end

  defp client(%{client: nil}), do: ""
  defp client(%{client: client}), do: " (#{client})"

  defp seconds(nil), do: "0.000"
  defp seconds(us), do: :erlang.float_to_binary(us / 1_000_000, decimals: 3)

  ## XML building

  defp element(tag, attrs, nil), do: ["<", tag, attributes(attrs), "/>\n"]

  # Text content goes right against the tags, so no whitespace leaks into it.
  defp element(tag, attrs, {:text, text}) do
    ["<", tag, attributes(attrs), ">", text, "</", tag, ">\n"]
  end

  defp element(tag, attrs, children) do
    case List.flatten(children) do
      [] -> element(tag, attrs, nil)
      _ -> ["<", tag, attributes(attrs), ">\n", children, "</", tag, ">\n"]
    end
  end

  defp attributes(attrs) do
    Enum.map(attrs, fn {key, value} ->
      [" ", Atom.to_string(key), "=\"", escape_attr(value), "\""]
    end)
  end

  defp text(""), do: nil
  defp text(value), do: {:text, escape(value)}

  defp escape_attr(value) do
    value
    |> escape()
    |> String.replace(["\n", "\r", "\t"], fn
      "\n" -> "&#10;"
      "\r" -> "&#13;"
      "\t" -> "&#9;"
    end)
  end

  # Escapes markup characters and drops anything XML 1.0 can't represent at
  # all (control characters a response body or `inspect/1` output can carry),
  # so the document always parses.
  defp escape(value) do
    value
    |> to_xml_string()
    |> String.replace(
      ~r/[^\x{9}\x{A}\x{D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]/u,
      ""
    )
    |> String.replace(["&", "<", ">", "\""], fn
      "&" -> "&amp;"
      "<" -> "&lt;"
      ">" -> "&gt;"
      "\"" -> "&quot;"
    end)
  end

  defp to_xml_string(value) when is_binary(value) do
    if String.valid?(value), do: value, else: inspect(value)
  end

  defp to_xml_string(value) when is_atom(value) or is_number(value), do: to_string(value)
  defp to_xml_string(value), do: inspect(value)
end
