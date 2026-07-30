defmodule MaestroWeb.ResourceComponents do
  @moduledoc """
  Shared read-only rendering for suites/scenarios/datasets/templates/test
  plans reused across every kind's `Index`/`Show` LiveView, and (later)
  Phase 3's forms.
  """

  use Phoenix.Component

  import MaestroWeb.CoreComponents

  @kinds [:suite, :scenario, :dataset, :template, :test_plan]

  @doc "Every resource kind's `{kind, plural_label, route_segment}`, in a stable display order."
  @spec resource_tiles() :: [{atom, String.t(), String.t()}]
  def resource_tiles do
    [
      {:suite, "Suites", "suites"},
      {:scenario, "Scenarios", "scenarios"},
      {:dataset, "Datasets", "datasets"},
      {:template, "Templates", "templates"},
      {:test_plan, "Test Plans", "test_plans"}
    ]
  end

  @doc "The route path segment for `kind` (e.g. `:test_plan` -> `\"test_plans\"`)."
  @spec route_segment(atom) :: String.t()
  def route_segment(kind) when kind in @kinds do
    Enum.find_value(resource_tiles(), fn {k, _label, segment} -> k == kind && segment end)
  end

  @doc "The kind for a route path segment (e.g. `\"test_plans\"` -> `:test_plan`), or `nil`."
  @spec kind_for_segment(String.t()) :: atom | nil
  def kind_for_segment(segment) when is_binary(segment) do
    Enum.find_value(resource_tiles(), fn {k, _label, s} -> s == segment && k end)
  end

  @doc "The plural display label for `kind` (e.g. `:test_plan` -> `\"Test Plans\"`)."
  @spec kind_label(atom) :: String.t()
  def kind_label(kind) when kind in @kinds do
    Enum.find_value(resource_tiles(), fn {k, label, _segment} -> k == kind && label end)
  end

  @doc """
  Renders the workspace drawer (see `MaestroWeb.Components.WorkspaceDrawer`)
  for `workspace`, highlighting `current_kind`/`current_path` if given (a
  `Show` page's own kind/path) so the tree auto-expands to and highlights
  whatever's currently on screen. Omit both on an `Index` page.
  """
  attr :workspace, :any, required: true
  attr :current_kind, :atom, default: nil
  attr :current_path, :string, default: nil

  def workspace_drawer(assigns) do
    ~H"""
    <.live_component
      module={MaestroWeb.Components.WorkspaceDrawer}
      id={"workspace-drawer-#{@workspace.id}"}
      workspace={@workspace}
      current_kind={@current_kind}
      current_path={@current_path}
    />
    """
  end

  @doc """
  Renders a form field label with an optional tooltip icon sourced from
  `Maestro.Resources.SchemaDocs.tooltip/2`, so form help text always
  matches the JSON Schema's own `description` rather than a hand-written
  (and easily stale) duplicate. Pure CSS/daisyUI `.tooltip` (hover-only,
  no JS) renders nothing if `kind`/`field_path` has no `description`.

  ## Examples

      <.field_label kind={:dataset} field_path={["data"]}>Data</.field_label>
  """
  attr :kind, :atom, required: true
  attr :field_path, :list, required: true
  slot :inner_block, required: true

  def field_label(assigns) do
    assigns =
      assign(
        assigns,
        :tooltip,
        Maestro.Resources.SchemaDocs.tooltip(assigns.kind, assigns.field_path)
      )

    ~H"""
    <span class="label mb-1 gap-1">
      {render_slot(@inner_block)}
      <span :if={@tooltip} class="tooltip tooltip-right" data-tip={@tooltip}>
        <.icon name="hero-question-mark-circle" class="size-3.5 text-base-content/50" />
      </span>
    </span>
    """
  end

  @doc """
  A `MaestroWeb.CoreComponents.input/1` whose label is `field_label/1`
  (schema-tooltip-aware) instead of a plain string. Takes the same
  `field`/`type`/etc. attrs as `<.input>`, plus `kind`/`field_path` to
  look up the tooltip.

  ## Examples

      <.tooltip_input field={@form[:name]} kind={:dataset} field_path={["name"]} label="Name" />
  """
  attr :kind, :atom, required: true
  attr :field_path, :list, required: true
  attr :label, :string, required: true
  attr :rest, :global

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  def tooltip_input(assigns) do
    ~H"""
    <div>
      <.field_label kind={@kind} field_path={@field_path}>{@label}</.field_label>
      <.input field={@field} {@rest} />
    </div>
    """
  end

  @doc """
  Renders a kind badge (small pill), e.g. for step lists showing whether an
  entry is a template-step or a scenario call.
  """
  attr :label, :string, required: true
  attr :class, :any, default: nil

  def kind_badge(assigns) do
    ~H"""
    <span class={["badge badge-soft badge-sm", @class]}>{@label}</span>
    """
  end

  @doc """
  Renders a dataset's body (either `data` a single key/value bag, or
  `rows` a table for data-driven iteration) read-only.
  """
  attr :dataset, :map, required: true

  def dataset_body(assigns) do
    ~H"""
    <div :if={data = @dataset["data"]} class="mb-4">
      <h4 class="font-semibold text-sm mb-1">data</h4>
      <.key_value_table map={data} />
    </div>
    <div :if={rows = @dataset["rows"]}>
      <h4 class="font-semibold text-sm mb-1">rows ({length(rows)})</h4>
      <.rows_table rows={rows} />
    </div>
    """
  end

  attr :map, :map, required: true

  def key_value_table(assigns) do
    ~H"""
    <table class="table table-sm table-zebra w-auto">
      <tbody>
        <tr :for={{key, value} <- @map}>
          <th class="whitespace-nowrap">{key}</th>
          <td>{inspect_value(value)}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  attr :rows, :list, required: true

  def rows_table(assigns) do
    columns = assigns.rows |> Enum.flat_map(&Map.keys/1) |> Enum.uniq()
    assigns = assign(assigns, :columns, columns)

    ~H"""
    <table class="table table-sm table-zebra">
      <thead>
        <tr>
          <th :for={col <- @columns}>{col}</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows}>
          <td :for={col <- @columns}>{inspect_value(Map.get(row, col))}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders one step (template-step or scenario-call, per `step.schema.json`'s
  `oneOf`) read-only, recursing into inline scenario/template/dataset bodies.
  """
  attr :step, :map, required: true
  attr :index, :integer, required: true

  def step_card(assigns) do
    ~H"""
    <div class="card bg-base-200 p-4 mb-2">
      <div class="flex items-center gap-2 mb-2">
        <span class="font-mono text-xs text-base-content/50">#{@index + 1}</span>
        <span class="font-semibold">{@step["name"] || step_default_name(@step)}</span>
        <.kind_badge :if={@step["scenario"]} label="scenario call" />
        <.kind_badge :if={@step["client"]} label={@step["client"]} />
      </div>

      <div :if={ref = scenario_ref(@step)} class="text-sm">
        <span class="text-base-content/70">scenario:</span>
        <span class="font-mono">{ref}</span>
      </div>
      <div :if={inline = inline_scenario(@step)} class="ml-4 border-l-2 border-base-300 pl-4">
        <.step_card :for={{s, i} <- Enum.with_index(inline["steps"] || [])} step={s} index={i} />
      </div>

      <div :if={ref = template_ref(@step)} class="text-sm">
        <span class="text-base-content/70">template:</span>
        <span class="font-mono">{ref}</span>
      </div>
      <div :if={inline = inline_template(@step)} class="text-sm">
        <span class="text-base-content/70">clients:</span> {Enum.join(inline["clients"] || [], ", ")}
        <pre class="mt-1 text-xs bg-base-100 rounded p-2 overflow-x-auto">{inspect_value(inline["payload"])}</pre>
      </div>

      <div :if={dataset = @step["dataset"]} class="text-sm mt-2">
        <span class="text-base-content/70">dataset:</span>
        <span :if={is_binary(dataset)} class="font-mono">{dataset}</span>
        <.dataset_body :if={is_map(dataset)} dataset={dataset} />
      </div>

      <div :for={{a, i} <- Enum.with_index(@step["assert"] || [])} class="text-sm mt-1">
        <span class="text-base-content/70">assert #{i + 1}:</span>
        <span class="font-mono">{a["matcher"] || "json_match"}</span>
        @ <span class="font-mono">{a["path"]}</span>
      </div>
    </div>
    """
  end

  defp step_default_name(%{"client" => client, "template" => template}) when is_binary(template),
    do: "#{client}: #{template}"

  defp step_default_name(%{"client" => client}), do: client
  defp step_default_name(%{"scenario" => scenario}) when is_binary(scenario), do: scenario
  defp step_default_name(_step), do: "(inline scenario)"

  defp scenario_ref(%{"scenario" => scenario}) when is_binary(scenario), do: scenario
  defp scenario_ref(_step), do: nil

  defp inline_scenario(%{"scenario" => scenario}) when is_map(scenario), do: scenario
  defp inline_scenario(_step), do: nil

  defp template_ref(%{"template" => template}) when is_binary(template), do: template
  defp template_ref(_step), do: nil

  defp inline_template(%{"template" => template}) when is_map(template), do: template
  defp inline_template(_step), do: nil

  defp inspect_value(value) when is_binary(value), do: value
  defp inspect_value(value), do: Jason.encode!(value)
end
