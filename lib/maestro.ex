defmodule Maestro do
  @moduledoc """
  """

  @type run_id :: term() ## Not decided yet

  @typedoc """
  A single entry in the list `run/1` accepts: a named suite reference (a
  file path, resolved via `Maestro.Resources.Resolver.resolve/1`), or an
  ad-hoc `t:suite/0` literal supplied directly, never persisted to a file.
  """
  @type suite_entry :: String.t() | suite()

  @typedoc """
  A single testcase within a suite (see `t:suite/0`):

      %{
        "id"                    => String.t(),
        "name"                  => String.t(),
        optional "description" => String.t(),
        "steps"                 => [step()]
      }

  `id` and `name` are both required (unlike a step's own optional
  `name`); `id` must be unique among the testcases in its suite —
  `Maestro.Resources.Resolver` enforces this at resolve time, not by this
  spec. `steps` reuses `t:step/0` loosely: before a suite is resolved (an
  ad-hoc suite passed to `run/1`, or one freshly read from a file), a
  step's `template`/`scenario`/`dataset` may still be unresolved
  reference strings rather than the fully-expanded bodies `t:step/0`
  describes — Dialyzer can't distinguish the two shapes either way (see
  `t:dataset_body/0`), so this type stands in for a step in both its pre-
  and post-resolution form.
  """
  @type testcase :: %{String.t() => term()}

  @typedoc """
  A Maestro test suite (see `priv/schemas/suite.schema.json`) — a named
  collection of testcases, either resolved (as returned by
  `Maestro.Resources.Resolver.resolve/1`) or not yet resolved (an ad-hoc
  suite literal passed to `run/1`, or one freshly read from a file):

      %{
        "id"                    => String.t(),
        optional "name"         => String.t(),
        optional "description"  => String.t(),
        optional "tags"         => [String.t()],
        "testcases"              => [testcase()]
      }

  `id` is required and is the suite's stable identity within a run,
  independent of its file path (which resolves the file) and of `name`
  (a purely display-only label) — see `priv/schemas/suite.schema.json`
  for the enforced schema; this type is the loose, string-keyed shape
  above (see `t:dataset_body/0` for why literal keys can't appear in the
  spec itself).
  """
  @type suite :: %{String.t() => term()}

  @typedoc """
  A single row, or a dataset's "data" bag — arbitrary JSON-decoded fields.
  """
  @type dataset_values :: %{String.t() => term()}

  @typedoc """
  A resolved dataset body (see `priv/schemas/dataset.schema.json#/$defs/body`
  and `Maestro.Resources.Resolver`) — always one shape or the other, never
  both, and never absent on a step that successfully resolved:

      %{"data" => dataset_values()}
      %{"rows" => [dataset_values()]}

  Elixir typespecs can't pin a map to specific literal string keys (no
  singleton type for binaries, unlike atoms/integers), so this is
  necessarily loose — the shape above is the real contract, enforced by
  `Maestro.Resources.Schemas`/`Maestro.Resources.Resolver` at runtime, not
  by this spec.
  """
  @type dataset_body :: %{String.t() => dataset_values() | [dataset_values()]}

  @typedoc "An assertion entry. Not implemented yet — accepted, currently ignored."
  @type assertion :: %{String.t() => term()}

  @typedoc """
  A `save` entry: extracts a value from a step's response into named state.

      %{"path" => String.t(), "as" => String.t()}
  """
  @type save_entry :: %{String.t() => String.t()}

  @typedoc """
  A resolved template body — the shape a `template` reference (file path or
  inline) resolves to, unchanged by resolution:

      %{
        optional "name"        => String.t(),
        optional "description" => String.t(),
        "clients"               => [String.t()],
        "payload"               => map() | String.t(),
        optional "options"     => map()
      }

  See `priv/schemas/template.schema.json#/$defs/body` for the enforced
  schema; this type is the loose, string-keyed shape above (see
  `t:dataset_body/0` for why literal keys can't appear in the spec itself).
  """
  @type resolved_template :: %{String.t() => term()}

  @typedoc """
  A resolved scenario body:

      %{
        optional "name"          => String.t(),
        optional "description"   => String.t(),
        "default_dataset"         => dataset_body(),
        "steps"                   => [step()]
      }

  `default_dataset` and `steps` are always present after resolution —
  `Maestro.Resources.Resolver` populates both unconditionally, even when
  the original scenario/call omitted a dataset or before `steps` were
  expanded. See `t:dataset_body/0` for why literal keys can't appear in
  the spec itself.
  """
  @type resolved_scenario :: %{String.t() => term()}

  @typedoc """
  A single entry in a fully resolved step sequence, as produced by
  `Maestro.Resources.Resolver` and consumed by `Maestro.Core.StepRunner` —
  either a template-step or a scenario-step:

      # template-step: renders `template` and dispatches to `client`
      %{
        optional "name"    => String.t(),
        "client"            => String.t(),
        "template"          => resolved_template(),
        "dataset"           => dataset_body(),
        optional "assert"  => [assertion()],
        optional "save"    => [save_entry()]
      }

      # scenario-step: recurses into the resolved scenario's own `steps`
      %{
        optional "name"    => String.t(),
        "scenario"          => resolved_scenario(),
        "dataset"           => dataset_body(),
        optional "assert"  => [assertion()]
      }

  `dataset` is always present on both shapes after resolution, even though
  it's optional pre-resolution on a scenario call — the Resolver merges
  and threads it down unconditionally. See `t:dataset_body/0` for why this
  can't be a precise, literal-keyed union at the typespec level.
  """
  @type step :: %{String.t() => term()}

  def run(_entries) do
  end

  def status(_run_id) do
  end

  def result(_run_id) do
  end
end
