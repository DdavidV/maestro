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

  @doc "A heroicon name representing `kind`, used in the sidebar, dashboard and page headers."
  @spec kind_icon(atom) :: String.t()
  def kind_icon(:suite), do: "hero-beaker"
  def kind_icon(:scenario), do: "hero-queue-list"
  def kind_icon(:dataset), do: "hero-table-cells"
  def kind_icon(:template), do: "hero-code-bracket"
  def kind_icon(:test_plan), do: "hero-clipboard-document-list"

  @doc "The singular display label for `kind` (e.g. `:test_plan` -> `\"Test plan\"`)."
  @spec kind_singular(atom) :: String.t()
  def kind_singular(:suite), do: "Suite"
  def kind_singular(:scenario), do: "Scenario"
  def kind_singular(:dataset), do: "Dataset"
  def kind_singular(:template), do: "Template"
  def kind_singular(:test_plan), do: "Test plan"

  @doc "A one-line explanation of what `kind` is, for the dashboard and empty states."
  @spec kind_description(atom) :: String.t()
  def kind_description(:suite), do: "Testcases made of ordered steps and assertions."
  def kind_description(:scenario), do: "Reusable step sequences shared across suites."
  def kind_description(:dataset), do: "Values or rows of data that steps render with."
  def kind_description(:template), do: "Payloads sent through a registered client."
  def kind_description(:test_plan), do: "Named groups of suites run together."

  @doc """
  Renders a breadcrumb trail: always starts with `workspace`'s own name
  (linking back to its dashboard, `/workspace/:id`), followed by `crumbs`
  a plain list of `{label, to_or_nil}` pairs, `to_or_nil` a navigate path
  or `nil` for the current (unlinked) step, always the trail's last entry
  in practice. Pass `crumbs={[]}` on the dashboard itself, so the
  workspace name is the trail's only (and therefore unlinked, current)
  entry there. The generic renderer every workspace-scoped page's own
  breadcrumb trail (see `resource_breadcrumbs/1`, or a page's own crumb
  list) ultimately builds against, so there's exactly one place the
  workspace-name-always-first rule and its styling/markup live.
  """
  attr :workspace, :any, required: true
  attr :crumbs, :list, required: true

  def breadcrumbs(assigns) do
    workspace_to = if assigns.crumbs == [], do: nil, else: "/workspace/#{assigns.workspace.id}"

    assigns =
      assign(assigns, :all_crumbs, [{assigns.workspace.name, workspace_to} | assigns.crumbs])

    ~H"""
    <nav aria-label="Breadcrumb" class="flex min-w-0 items-center gap-1.5 text-sm">
      <%= for {{label, to}, index} <- Enum.with_index(@all_crumbs) do %>
        <.icon
          :if={index > 0}
          name="hero-chevron-right-mini"
          class="size-4 shrink-0 text-base-content/30"
        />
        <.link
          :if={to}
          navigate={to}
          class="truncate text-base-content/60 transition-colors hover:text-base-content"
        >{label}</.link>
        <span :if={!to} class="truncate font-medium text-base-content">{label}</span>
      <% end %>
    </nav>
    """
  end

  @doc """
  Renders a breadcrumb trail for one resource kind's Index/Show/New/Edit
  pages (e.g. "Suites > checkout/smoke > Edit"), each crumb but the last
  a link back to that step. A nested path (`"checkout/smoke"`) is kept as
  one crumb, not split per path segment there's no per-folder listing
  page today for a "checkout" crumb to link to.
  """
  attr :workspace, :any, required: true
  attr :kind, :atom, required: true
  attr :segment, :string, required: true
  attr :path, :string, default: nil
  attr :live_action, :atom, required: true

  def resource_breadcrumbs(assigns) do
    assigns = assign(assigns, :crumbs, resource_breadcrumb_crumbs(assigns))

    ~H"""
    <.breadcrumbs workspace={@workspace} crumbs={@crumbs} />
    """
  end

  defp resource_breadcrumb_crumbs(%{
         workspace: workspace,
         kind: kind,
         segment: segment,
         path: path,
         live_action: live_action
       }) do
    index_path = "/workspace/#{workspace.id}/#{segment}"
    label = kind_label(kind)

    case live_action do
      :index ->
        [{label, nil}]

      :show ->
        [{label, index_path}, {path, nil}]

      :new ->
        [{label, index_path}, {"New", nil}]

      :edit ->
        [{label, index_path}, {path, "#{index_path}/#{path}"}, {"Edit", nil}]
    end
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
    <span class="label mb-1.5 gap-1 text-xs font-medium text-base-content/80">
      {render_slot(@inner_block)}
      <span :if={@tooltip} class="tooltip tooltip-right font-normal" data-tip={@tooltip}>
        <.icon name="hero-question-mark-circle-mini" class="size-3.5 text-base-content/40" />
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
    <span class={[
      "inline-flex items-center rounded-md border border-base-300 bg-base-200 px-1.5 py-0.5 text-xs font-medium text-base-content/70",
      @class
    ]}>{@label}</span>
    """
  end

  @doc """
  Renders a dataset's body (either `data` a single key/value bag, or
  `rows` a table for data-driven iteration) read-only.
  """
  attr :dataset, :map, required: true

  def dataset_body(assigns) do
    ~H"""
    <div :if={data = @dataset["data"]} class="space-y-2">
      <div class="section-label">
        Data · {map_size(data)} {if map_size(data) == 1, do: "field", else: "fields"}
      </div>
      <.key_value_table map={data} />
    </div>
    <div :if={rows = @dataset["rows"]} class="space-y-2">
      <div class="section-label">Rows · {length(rows)}</div>
      <.rows_table rows={rows} />
    </div>
    """
  end

  attr :map, :map, required: true

  def key_value_table(assigns) do
    ~H"""
    <div class="overflow-x-auto rounded-field border border-base-300 bg-base-100">
      <table class="w-full text-sm">
        <tbody class="divide-y divide-base-300">
          <tr :for={{key, value} <- @map}>
            <th class="w-1/3 whitespace-nowrap bg-base-200/60 px-3 py-2 text-left align-top font-mono text-xs font-medium text-base-content/70">
              {key}
            </th>
            <td class="px-3 py-2 font-mono text-xs break-all">{inspect_value(value)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :rows, :list, required: true

  def rows_table(assigns) do
    columns = assigns.rows |> Enum.flat_map(&Map.keys/1) |> Enum.uniq()
    assigns = assign(assigns, :columns, columns)

    ~H"""
    <div class="overflow-x-auto rounded-field border border-base-300 bg-base-100">
      <table class="w-full text-sm">
        <thead class="bg-base-200/60">
          <tr>
            <th class="w-10 px-3 py-2 text-left font-mono text-xs font-medium text-base-content/40">
              #
            </th>
            <th
              :for={col <- @columns}
              class="px-3 py-2 text-left font-mono text-xs font-medium text-base-content/70 whitespace-nowrap"
            >
              {col}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-base-300 border-t border-base-300">
          <tr :for={{row, i} <- Enum.with_index(@rows, 1)}>
            <td class="px-3 py-2 font-mono text-xs text-base-content/40">{i}</td>
            <td :for={col <- @columns} class="px-3 py-2 font-mono text-xs">
              {inspect_value(Map.get(row, col))}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
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
    <div class="relative flex gap-3">
      <div class="flex flex-col items-center">
        <span class={[
          "grid size-6 shrink-0 place-items-center rounded-full border text-[0.6875rem] font-semibold",
          if(@step["scenario"],
            do: "border-accent/30 bg-accent/10 text-accent",
            else: "border-base-300 bg-base-100 text-base-content/60"
          )
        ]}>
          {@index + 1}
        </span>
        <span class="mt-1 w-px flex-1 bg-base-300 group-last/step:hidden" />
      </div>

      <div class="min-w-0 flex-1 pb-4">
        <div class="flex flex-wrap items-center gap-2 pt-0.5">
          <span class="font-medium">{@step["name"] || step_default_name(@step)}</span>
          <span
            :if={@step["scenario"]}
            class="inline-flex items-center gap-1 rounded-md bg-accent/10 px-1.5 py-0.5 text-xs font-medium text-accent"
          >
            <.icon name="hero-queue-list-micro" class="size-3" /> scenario call
          </span>
          <.kind_badge :if={@step["client"]} label={@step["client"]} class="font-mono" />
        </div>

        <dl class="mt-2 grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 text-sm">
          <.step_ref :if={ref = scenario_ref(@step)} label="Scenario" value={ref} />
          <.step_ref :if={ref = template_ref(@step)} label="Template" value={ref} />
          <%= if inline = inline_template(@step) do %>
            <dt class="text-base-content/50">Template</dt>
            <dd class="min-w-0 space-y-1.5">
              <span class="text-xs text-base-content/60">
                inline · clients: {Enum.join(inline["clients"] || [], ", ")}
              </span>
              <pre class="code-block text-xs">{Jason.encode!(inline["payload"], pretty: true)}</pre>
            </dd>
          <% end %>
          <.step_ref
            :if={is_binary(@step["dataset"])}
            label="Dataset"
            value={@step["dataset"]}
          />
          <%= if is_map(@step["dataset"]) do %>
            <dt class="text-base-content/50">Dataset</dt>
            <dd class="min-w-0 space-y-3"><.dataset_body dataset={@step["dataset"]} /></dd>
          <% end %>
          <%= if (@step["assert"] || []) != [] do %>
            <dt class="text-base-content/50">Asserts</dt>
            <dd class="min-w-0 space-y-1">
              <div
                :for={a <- @step["assert"] || []}
                class="flex flex-wrap items-center gap-1.5 text-xs"
              >
                <.icon name="hero-check-badge-micro" class="size-3.5 text-base-content/40" />
                <span class="font-mono font-medium">{a["matcher"] || "json_match"}</span>
                <span class="text-base-content/40">@</span>
                <code class="font-mono text-base-content/70">{a["path"]}</code>
              </div>
            </dd>
          <% end %>
        </dl>

        <div
          :if={inline = inline_scenario(@step)}
          class="mt-3 rounded-field border border-base-300 p-3"
        >
          <div class="section-label mb-3">Inline scenario</div>
          <div
            :for={{s, i} <- Enum.with_index(inline["steps"] || [])}
            class="group/step"
          >
            <.step_card step={s} index={i} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp step_ref(assigns) do
    ~H"""
    <dt class="text-base-content/50">{@label}</dt>
    <dd class="min-w-0 truncate font-mono text-[0.8125rem]">{@value}</dd>
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
