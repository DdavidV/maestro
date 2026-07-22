defmodule Maestro do
  @moduledoc """
  Maestro's main API, and the home of the types used throughout Maestro.
  """

  @typedoc """
  A single entry in the list `run/1` accepts: a named suite reference (a
  file path, resolved via `Maestro.Resources.Resolver.resolve/1`), or an
  ad-hoc suite literal supplied directly, never persisted to a file. Either
  way this is the *unresolved* form, JSON-decoded, string-keyed, and
  possibly still holding reference strings for its templates/scenarios/
  datasets. `run/1` sends it through `Maestro.Resources.Resolver.resolve/1`
  the same as a file-based suite before it's runnable. See `t:suite/0` for
  the resolved shape.
  """
  @type suite_entry :: String.t() | map()

  @typedoc """
  A resolved Maestro test suite, as returned by
  `Maestro.Resources.Resolver.resolve/1` (see `priv/schemas/suite.schema.json`).
  `id` is required and is the suite's stable identity within a run,
  independent of its file path (which resolves the file)
  and of `name` (a purely display-only label).
  """
  @type suite :: %{
          required(:id) => String.t(),
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:tags) => [String.t()],
          required(:testcases) => [testcase()]
        }

  @typedoc """
  A single testcase within a resolved suite (see `t:suite/0`). `id` is
  required and must be unique among the testcases in its suite,
  `Maestro.Resources.Resolver` enforces this at resolve time.
  `name` is purely a display label, same as `t:suite/0`'s.
  """
  @type testcase :: %{
          required(:id) => String.t(),
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          required(:steps) => [step()]
        }

  @typedoc """
  A single entry in a fully resolved step sequence, as produced by
  `Maestro.Resources.Resolver` and consumed by `Maestro.Core.StepRunner`.
  Either a `t:template_step/0` (renders `template` and dispatches to `client`)
  or a `t:scenario_step/0` (recurses into the resolved scenario's own `steps`).
  `dataset` is always present on both shapes after resolution, even though it's
  optional pre-resolution on a scenario call the Resolver merges and threads it down
  unconditionally.
  """
  @type step :: template_step() | scenario_step()

  @type template_step :: %{
          optional(:name) => String.t(),
          required(:client) => String.t(),
          required(:template) => resolved_template(),
          required(:dataset) => dataset_body(),
          optional(:assert) => [assertion()],
          optional(:save) => [save_entry()]
        }

  @type scenario_step :: %{
          optional(:name) => String.t(),
          required(:scenario) => resolved_scenario(),
          required(:dataset) => dataset_body(),
          optional(:assert) => [assertion()]
        }

  @typedoc """
  A resolved template body, the shape a `template` reference (file path or
  inline) resolves to. (See `priv/schemas/template.schema.json#/$defs/body`).
  `options` is always present after resolution (defaults to `%{}` if the author omitted it)
  `payload`'s (and `options`'s) own fields are an open, author-defined vocabulary filled in
  by interpolation.
  """
  @type resolved_template :: %{
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          required(:clients) => [String.t()],
          required(:payload) => map() | String.t(),
          required(:options) => map()
        }

  @typedoc """
  A resolved scenario body. `default_dataset` and `steps` are always
  present after resolution `Maestro.Resources.Resolver` populates both
  unconditionally, even when the original scenario/call omitted a dataset.
  """
  @type resolved_scenario :: %{
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          required(:default_dataset) => dataset_body(),
          required(:steps) => [step()]
        }

  @typedoc """
  A resolved dataset body (see `priv/schemas/dataset.schema.json#/$defs/body`
  and `Maestro.Resources.Resolver`) always one shape or the other, never
  both, and never absent on a step that successfully resolved.
  """
  @type dataset_body :: %{data: dataset_values()} | %{rows: [dataset_values()]}

  @typedoc """
  A single row, or a dataset's "data" bag arbitrary JSON-decoded fields.
  Field names are author-defined and open-ended.
  """
  @type dataset_values :: %{String.t() => term()}

  @typedoc """
  A `save` entry: extracts a value from a step's response into named state.
  """
  @type save_entry :: %{path: String.t(), as: String.t()}

  @typedoc "An assertion entry. Not implemented yet and currently ignored."
  @type assertion :: %{String.t() => term()}

  def run(_entries) do
  end

  def status(_run_id) do
  end

  def result(_run_id) do
  end
end
