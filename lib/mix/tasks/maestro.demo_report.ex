defmodule Mix.Tasks.Maestro.DemoReport do
  @shortdoc "Generates a full showcase HTML report for eyeballing Maestro.Report.DefaultLayout"

  @moduledoc """
  Runs a real `Maestro.run/1` against a handful of hand-built demo suites
  covering every reportable outcome, then writes the resulting HTML report
  to a fixed, predictable path so developers can just open the same file
  after every regeneration instead of hunting for a `run_id`-named one:

  ```bash
  mix maestro.demo_report
  ```

  Writes to `tmp/reports/showcase.html` under the project root (see
  `report_path/0`), overwriting any previous run. Disables automatic
  report generation for this run (`auto_report: false`) and renders/writes
  the report directly at the fixed path instead, so this task's demo runs
  never clutter the real `report_dir`/`priv/reports`.

  Demo suites, one per reportable scenario:

    * `passing_suite` a straightforward all-green suite (multiple
      passing testcases/steps/assertions), including a step with no
      `assert` entries at all (proving those still render).
    * `failing_suite` one testcase per distinct `reason` atom
      `Maestro.Matchers.JsonMatch` can produce (see its moduledoc's
      "Failure reporting" table) each testcase's step is named after the
      `reason` it triggers, so every kind of `json_match` failure is
      visible in the report in isolation, plus one testcase specifically
      showing several mismatches accumulated onto a single assertion
      (multiple `Reason` entries, not just the first).
    * `schema_failing_suite` a `json_schema_match` assertion against a
      response that violates several schema rules at once, same
      multi-violation idea via a different matcher.
    * `dispatch_error_suite` a step naming an unregistered client, so
      `Maestro.Client.Error` renders (`stage: :client_lookup`).
    * `client_crash_suite` a step whose client module raises inside
      `send/2` demonstrates the crash is caught and rendered as a normal
      `Maestro.Client.Error` (`stage: :send, reason: :client_raised`),
      not a broken report or a hung run.

  This is a developer tool, not a test: nothing here is asserted against,
  it exists purely to produce a real, inspectable HTML file while
  iterating on `Maestro.Report.DefaultLayout` (or a custom
  `Maestro.Report.Layout`, via `--layout`).
  """

  use Mix.Task

  alias Maestro.Core.Runner

  defmodule DemoCrashingClient do
    @moduledoc false
    use Maestro.Client, name: "maestro_demo_crashing_client"

    def send(_call_state, _rendered), do: raise("demo client crash: simulated outage")
  end

  defmodule DemoOkClient do
    @moduledoc false
    use Maestro.Client, name: "maestro_demo_ok_client"

    def send(_call_state, rendered), do: {:ok, %{"echo" => rendered}}
  end

  defmodule Checks do
    @moduledoc false
    def always_false(_actual), do: false
    def weird_result(_actual), do: :not_a_valid_result
  end

  @report_path Path.join([File.cwd!(), "tmp", "reports", "showcase.html"])

  @doc "The fixed path this task always writes to."
  @spec report_path() :: String.t()
  def report_path, do: @report_path

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [layout: :string])
    layout = resolve_layout(opts[:layout])

    Application.put_env(:maestro, :auto_report, false)

    {:ok, run_id} = Runner.run(demo_suites())
    final = wait_until_done(run_id)

    Mix.shell().info("Demo run #{run_id} finished: #{final.status}")

    File.mkdir_p!(Path.dirname(@report_path))

    case Maestro.render_report(run_id, layout) do
      {:ok, html} ->
        File.write!(@report_path, html)
        Mix.shell().info("Wrote showcase report to #{@report_path}")

      {:error, reason} ->
        Mix.raise("Failed to render demo report: #{inspect(reason)}")
    end
  end

  defp resolve_layout(nil), do: Maestro.Report.Layout.configured()

  defp resolve_layout(module_name) do
    Module.concat([module_name])
  end

  defp wait_until_done(run_id, tries \\ 200) do
    {:ok, progress} = Runner.status(run_id)

    if progress.status in [:ok, :error] or tries == 0 do
      progress
    else
      Process.sleep(20)
      wait_until_done(run_id, tries - 1)
    end
  end

  defp demo_suites do
    [
      passing_suite(),
      failing_suite(),
      schema_failing_suite(),
      dispatch_error_suite(),
      client_crash_suite()
    ]
  end

  defp ok_step(name, payload) do
    %{
      "name" => name,
      "client" => "maestro_demo_ok_client",
      "template" => %{"clients" => ["maestro_demo_ok_client"], "payload" => payload},
      "dataset" => %{"data" => payload}
    }
  end

  defp passing_suite do
    %{
      "id" => "passing_suite",
      "testcases" => [
        %{
          "id" => "everything_passes",
          "steps" => [
            Map.put(
              ok_step("check status", %{"status" => "ok"}),
              "assert",
              [
                %{
                  "matcher" => "json_match",
                  "path" => "$.echo.payload.status",
                  "expected" => "ok"
                }
              ]
            ),
            ok_step("step with no assertions", %{"noop" => true})
          ]
        }
      ]
    }
  end

  # One json_match assertion, wrapped in a testcase whose id is the
  # reason atom being demonstrated. `payload` is what the demo client
  # echoes back (so `$.echo.payload...` is the actual under test);
  # `assertion` is the single json_match assert entry that fails with
  # exactly that reason.
  defp json_match_case(reason_atom, payload, assertion) do
    %{
      "id" => Atom.to_string(reason_atom),
      "steps" => [
        Map.put(
          ok_step("reason: #{reason_atom}", payload),
          "assert",
          [Map.put(assertion, "matcher", "json_match")]
        )
      ]
    }
  end

  defp failing_suite do
    %{
      "id" => "failing_suite",
      "testcases" => [
        json_match_case(:not_equal, %{"status" => "pending"}, %{
          "path" => "$.echo.payload.status",
          "expected" => "confirmed"
        }),
        json_match_case(:object_expected, %{"status" => "pending"}, %{
          "path" => "$.echo.payload.status",
          "expected" => %{"nested" => "object"}
        }),
        json_match_case(:list_expected, %{"tags" => "not-a-list"}, %{
          "path" => "$.echo.payload.tags",
          "expected" => [1, 2, 3]
        }),
        json_match_case(:expected_key_missing, %{"id" => 1}, %{
          "path" => "$.echo.payload",
          "expected" => %{"id" => 1, "status" => "$expected"}
        }),
        json_match_case(:unexpected_key_present, %{"id" => 1, "internal" => "leaked"}, %{
          "path" => "$.echo.payload",
          "expected" => %{"id" => 1, "internal" => "$unexpected"}
        }),
        json_match_case(:invalid_closed_object_directive, %{"id" => 1}, %{
          "path" => "$.echo.payload",
          "expected" => %{"id" => 1, "$_" => true}
        }),
        json_match_case(:unexpected_extra_keys, %{"id" => 1, "extra" => "field"}, %{
          "path" => "$.echo.payload",
          "expected" => %{"id" => 1, "$_" => "$unexpected"}
        }),
        json_match_case(:length_mismatch, %{"items" => [1, 2]}, %{
          "path" => "$.echo.payload.items",
          "expected" => [1, 2, 3]
        }),
        json_match_case(:invalid_unexpected_position, %{"items" => [1, 2, 3]}, %{
          "path" => "$.echo.payload.items",
          "expected" => [1, "$unexpected", 3]
        }),
        json_match_case(:contains_item_not_found, %{"tags" => [1, 2, 3]}, %{
          "path" => "$.echo.payload.tags",
          "expected" => %{"$contains" => [1, 99]}
        }),
        json_match_case(:excluded_item_found, %{"tags" => [1, 2, 3]}, %{
          "path" => "$.echo.payload.tags",
          "expected" => %{"$excludes" => [1, 5]}
        }),
        json_match_case(:length_not_equal, %{"items" => [1, 2]}, %{
          "path" => "$.echo.payload.items",
          "expected" => %{"$length" => 3}
        }),
        json_match_case(:length_not_greater_than, %{"items" => [1, 2]}, %{
          "path" => "$.echo.payload.items",
          "expected" => %{"$length" => %{"$gt" => 2}}
        }),
        json_match_case(:length_not_less_than, %{"items" => [1, 2, 3]}, %{
          "path" => "$.echo.payload.items",
          "expected" => %{"$length" => %{"$lt" => 3}}
        }),
        json_match_case(:length_not_between, %{"items" => [1]}, %{
          "path" => "$.echo.payload.items",
          "expected" => %{"$length" => %{"$between" => [2, 4]}}
        }),
        json_match_case(:invalid_length_directive, %{"items" => [1, 2]}, %{
          "path" => "$.echo.payload.items",
          "expected" => %{"$length" => "not-a-valid-spec"}
        }),
        json_match_case(:regex_no_match, %{"code" => "abc"}, %{
          "path" => "$.echo.payload.code",
          "expected" => %{"$regex" => "^ORD-\\d+$"}
        }),
        json_match_case(:invalid_regex, %{"code" => "abc"}, %{
          "path" => "$.echo.payload.code",
          "expected" => %{"$regex" => "(unclosed"}
        }),
        json_match_case(:mfa_check_failed, %{"code" => "abc"}, %{
          "path" => "$.echo.payload.code",
          "expected" => %{
            "$mfa" => %{
              "module" => "Mix.Tasks.Maestro.DemoReport.Checks",
              "function" => "always_false"
            }
          }
        }),
        json_match_case(:invalid_mfa_result, %{"code" => "abc"}, %{
          "path" => "$.echo.payload.code",
          "expected" => %{
            "$mfa" => %{
              "module" => "Mix.Tasks.Maestro.DemoReport.Checks",
              "function" => "weird_result"
            }
          }
        }),
        json_match_case(:mfa_error, %{"code" => "abc"}, %{
          "path" => "$.echo.payload.code",
          "expected" => %{
            "$mfa" => %{"module" => "DoesNotExistAtAll", "function" => "whatever"}
          }
        }),
        json_match_case(:invalid_mfa_directive, %{"code" => "abc"}, %{
          "path" => "$.echo.payload.code",
          "expected" => %{"$mfa" => %{"module" => "OnlyModuleNoFunction"}}
        }),
        json_match_case(:interpolation_failed, %{"code" => "abc"}, %{
          "path" => "$.echo.payload.code",
          "expected" => "{{never_defined}}"
        }),
        json_match_case(:path_not_found, %{"code" => "abc"}, %{
          "path" => "$.echo.payload.does_not_exist",
          "expected" => "anything"
        }),
        %{
          "id" => "accumulates_multiple_mismatches_on_one_assertion",
          "steps" => [
            Map.put(
              ok_step("several wrong fields at once", %{
                "id" => 1,
                "status" => "pending",
                "total" => 100
              }),
              "assert",
              [
                %{
                  "matcher" => "json_match",
                  "path" => "$.echo.payload",
                  "expected" => %{"id" => 1, "status" => "confirmed", "total" => 90}
                }
              ]
            )
          ]
        }
      ]
    }
  end

  defp schema_failing_suite do
    %{
      "id" => "schema_failing_suite",
      "testcases" => [
        %{
          "id" => "response_violates_schema",
          "steps" => [
            Map.put(
              ok_step("post user", %{"id" => "not-an-integer", "email" => 12_345}),
              "assert",
              [
                %{
                  "matcher" => "json_schema_match",
                  "path" => "$.echo.payload",
                  "expected" => %{
                    "type" => "object",
                    "required" => ["id", "email"],
                    "properties" => %{
                      "id" => %{"type" => "integer"},
                      "email" => %{"type" => "string"}
                    }
                  }
                }
              ]
            )
          ]
        }
      ]
    }
  end

  defp dispatch_error_suite do
    %{
      "id" => "dispatch_error_suite",
      "testcases" => [
        %{
          "id" => "unregistered_client",
          "steps" => [
            %{
              "name" => "call a client that was never registered",
              "client" => "maestro_demo_does_not_exist",
              "template" => %{"clients" => ["maestro_demo_does_not_exist"], "payload" => %{}},
              "dataset" => %{"data" => %{"marker" => "dispatch_error"}}
            }
          ]
        }
      ]
    }
  end

  defp client_crash_suite do
    %{
      "id" => "client_crash_suite",
      "testcases" => [
        %{
          "id" => "client_raises",
          "steps" => [
            %{
              "name" => "call a client that crashes",
              "client" => "maestro_demo_crashing_client",
              "template" => %{"clients" => ["maestro_demo_crashing_client"], "payload" => %{}},
              "dataset" => %{"data" => %{"marker" => "client_crash"}}
            }
          ]
        }
      ]
    }
  end
end
