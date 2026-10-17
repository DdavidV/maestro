defmodule MaestroWeb.Components.FormFields do
  @moduledoc """
  Per-kind form field groups for `MaestroWeb.WorkspaceLive.Form`, one
  function component per group of fields.

  Every event these emit (`phx-click`/`phx-change`) is handled directly by
  `MaestroWeb.WorkspaceLive.Form`.
  """

  use Phoenix.Component

  import MaestroWeb.CoreComponents
  import MaestroWeb.ResourceComponents, only: [field_label: 1]

  alias MaestroWeb.WorkspaceLive.Form

  @doc "The `id`/`name`/`description` fields shared by `:suite` and `:test_plan` (both require `id`)."
  attr :kind, :atom, required: true
  attr :data, :map, required: true

  def top_level_fields(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <.field_label kind={@kind} field_path={["id"]}>Id</.field_label>
      <input
        type="text"
        value={@data["id"]}
        phx-change="update-id"
        name="resource_id"
        placeholder="e.g. checkout-smoke"
        class="w-full input font-mono text-[0.8125rem]"
      />
    </div>

    <.name_description_fields kind={@kind} data={@data} />
    """
  end

  @doc "The `name`/`description` fields shared by `:dataset`, `:scenario`, `:template`, `:suite`, `:test_plan`."
  attr :kind, :atom, required: true
  attr :data, :map, required: true

  def name_description_fields(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <.field_label kind={@kind} field_path={["name"]}>Name</.field_label>
      <input
        type="text"
        value={@data["name"]}
        phx-change="update-name"
        name="name"
        class="w-full input"
      />
    </div>

    <div class="fieldset mb-2">
      <.field_label kind={@kind} field_path={["description"]}>Description</.field_label>
      <textarea
        phx-change="update-description"
        name="description"
        rows="2"
        placeholder="What does this cover?"
        class="w-full textarea"
      >{@data["description"]}</textarea>
    </div>
    """
  end

  @doc """
  Dataset body: `data` as a key/value repeater (`@data_pairs`), `rows` as a
  fixed-shared-column table (`@row_columns`). A dataset must be exactly
  one or the other, never both (`dataset.schema.json`'s `oneOf`), so
  `@dataset_mode` (`"data"` or `"rows"`) gates which section is shown/
  editable switching modes clears the other one's data immediately
  (`"dataset-set-mode"` in `WorkspaceLive.Form`) rather than leaving stale
  data to be silently dropped at save time.
  """
  attr :data, :map, required: true
  attr :dataset_mode, :string, required: true
  attr :data_pairs, :list, required: true
  attr :row_columns, :list, required: true
  attr :errors, :list, required: true

  def dataset_fields(assigns) do
    ~H"""
    <div class="mb-5">
      <div class="inline-grid grid-cols-2 gap-1 rounded-field bg-base-200 p-1">
        <button
          :for={
            {mode, label, icon} <- [
              {"data", "Single value", "hero-list-bullet-mini"},
              {"rows", "Table of rows", "hero-table-cells-mini"}
            ]
          }
          type="button"
          class={[
            "flex items-center justify-center gap-1.5 rounded-[calc(var(--radius-field)-2px)] px-3 py-1.5 text-sm font-medium transition",
            if(@dataset_mode == mode,
              do: "bg-base-100 shadow-xs",
              else: "text-base-content/60 hover:text-base-content"
            )
          ]}
          phx-click="dataset-set-mode"
          phx-value-mode={mode}
        >
          <.icon name={icon} class="size-4" /> {label}
        </button>
      </div>
      <p class="mt-2 text-xs text-base-content/60">
        <span :if={@dataset_mode == "data"}>
          One fixed set of key/value pairs, used as-is wherever this dataset is referenced.
        </span>
        <span :if={@dataset_mode == "rows"}>
          A table of rows with shared columns a step or scenario using this dataset runs once
          per row.
        </span>
      </p>
    </div>

    <div :if={@dataset_mode == "data"}>
      <div class="mb-2 flex items-center justify-between">
        <.field_label kind={:dataset} field_path={["data"]}>Data</.field_label>
        <.button phx-click="dataset-add-data-field">
          <.icon name="hero-plus-mini" class="size-4" /> Add field
        </.button>
      </div>

      <div :for={{{key, value}, index} <- Enum.with_index(@data_pairs)} class="flex gap-2 mb-2">
        <input
          type="text"
          value={key}
          placeholder="key"
          phx-change="dataset-update-data-field-key"
          name={"data_pairs[#{index}][key]"}
          class="input flex-1 font-mono text-[0.8125rem]"
        />
        <input
          type="text"
          value={value}
          placeholder="value"
          phx-change="dataset-update-data-field-value"
          name={"data_pairs[#{index}][value]"}
          class="input flex-1"
        />
        <.button
          variant="ghost"
          class="btn-square text-base-content/40 hover:text-error"
          phx-click="dataset-remove-data-field"
          phx-value-index={index}
          aria-label="Remove field"
        >
          <.icon name="hero-trash-mini" class="size-4" />
        </.button>
      </div>

      <p
        :if={@data_pairs == []}
        class="rounded-field border border-dashed border-base-300 px-4 py-6 text-center text-sm text-base-content/60"
      >
        No fields yet. Click "Add field" to add a key/value pair (e.g.
        <span class="font-mono">username</span>
        / <span class="font-mono">alice</span>).
      </p>
    </div>

    <div :if={@dataset_mode == "rows"}>
      <div class="mb-2 flex items-center justify-between">
        <.field_label kind={:dataset} field_path={["rows"]}>Rows</.field_label>
        <div class="flex gap-2">
          <.button phx-click="dataset-add-column">
            <.icon name="hero-view-columns-mini" class="size-4" /> Add column
          </.button>
          <.button phx-click="dataset-add-row" disabled={@row_columns == []}>
            <.icon name="hero-plus-mini" class="size-4" /> Add row
          </.button>
        </div>
      </div>

      <div :if={@row_columns != []} class="overflow-x-auto rounded-field border border-base-300">
        <table class="table table-sm">
          <thead>
            <tr>
              <th :for={{column, col_index} <- Enum.with_index(@row_columns)}>
                <div class="flex gap-1 items-center">
                  <input
                    type="text"
                    value={column}
                    placeholder="column name"
                    phx-change="dataset-rename-column"
                    name={"row_columns[#{col_index}]"}
                    class="input input-sm font-mono"
                  />
                  <.button
                    variant="ghost"
                    size="xs"
                    class="btn-square text-base-content/40 hover:text-error"
                    phx-click="dataset-remove-column"
                    phx-value-index={col_index}
                    aria-label="Remove column"
                  >
                    <.icon name="hero-x-mark-mini" class="size-3.5" />
                  </.button>
                </div>
              </th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{row, row_index} <- Enum.with_index(@data["rows"] || [])}>
              <td :for={column <- @row_columns}>
                <input
                  type="text"
                  value={Map.get(row, column, "")}
                  phx-change="dataset-update-row-field"
                  name={"rows[#{row_index}][#{column}]"}
                  class="input input-sm"
                />
              </td>
              <td>
                <.button
                  variant="ghost"
                  size="xs"
                  class="btn-square text-base-content/40 hover:text-error"
                  phx-click="dataset-remove-row"
                  phx-value-index={row_index}
                  aria-label="Remove row"
                >
                  <.icon name="hero-trash-mini" class="size-3.5" />
                </.button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p
        :if={@row_columns == []}
        class="rounded-field border border-dashed border-base-300 px-4 py-6 text-center text-sm text-base-content/60"
      >
        No columns yet. Click "Add column" to name your first column (e.g. <span class="font-mono">username</span>), then "Add row" to start filling in values.
      </p>
    </div>

    <p :if={msg = Form.error_for(@errors, "#")} class="mt-2 text-sm text-error">{msg}</p>
    """
  end

  @doc "Template body: clients multi-select + raw-JSON payload/options textareas."
  attr :data, :map, required: true
  attr :client_names, :list, required: true
  attr :payload_raw, :string, required: true
  attr :payload_error, :string, default: nil
  attr :options_raw, :string, required: true
  attr :options_error, :string, default: nil

  def template_fields(assigns) do
    ~H"""
    <div class="mb-4">
      <.field_label kind={:template} field_path={["clients"]}>Clients</.field_label>
      <div class="flex flex-wrap gap-2">
        <label
          :for={client <- @client_names}
          class={[
            "flex cursor-pointer items-center gap-2 rounded-field border px-2.5 py-1.5 font-mono text-[0.8125rem] transition-colors",
            if(client in (@data["clients"] || []),
              do: "border-primary/40 bg-primary/5",
              else: "border-base-300 hover:bg-base-200"
            )
          ]}
        >
          <input
            type="checkbox"
            checked={client in (@data["clients"] || [])}
            phx-click="template-toggle-client"
            phx-value-client={client}
            class="checkbox checkbox-xs checkbox-primary"
          />
          {client}
        </label>
      </div>
      <p :if={@client_names == []} class="text-sm text-base-content/70 mt-1">
        No clients registered.
      </p>
    </div>

    <div class="fieldset mb-2">
      <.field_label kind={:template} field_path={["payload"]}>Payload (JSON)</.field_label>
      <textarea
        phx-change="template-update-payload"
        name="payload"
        class={[
          "w-full textarea font-mono text-[0.8125rem] leading-relaxed",
          @payload_error && "textarea-error"
        ]}
        rows="10"
      >{@payload_raw}</textarea>
      <p :if={@payload_error} class="mt-1.5 flex gap-1.5 items-center text-xs text-error">
        <.icon name="hero-exclamation-circle-mini" class="size-4" />{@payload_error}
      </p>
    </div>

    <div class="fieldset mb-2">
      <.field_label kind={:template} field_path={["options"]}>Options (JSON)</.field_label>
      <textarea
        phx-change="template-update-options"
        name="options"
        class={[
          "w-full textarea font-mono text-[0.8125rem] leading-relaxed",
          @options_error && "textarea-error"
        ]}
        rows="6"
      >{@options_raw}</textarea>
      <p :if={@options_error} class="mt-1.5 flex gap-1.5 items-center text-xs text-error">
        <.icon name="hero-exclamation-circle-mini" class="size-4" />{@options_error}
      </p>
    </div>
    """
  end

  @doc "Scenario body: optional `default_dataset` (via `ReferencePicker`) + its step list."
  attr :workspace, :any, required: true
  attr :data, :map, required: true
  attr :client_names, :list, required: true
  attr :expected_raw, :map, required: true
  attr :errors, :list, required: true

  def scenario_fields(assigns) do
    ~H"""
    <section class="panel">
      <div class="panel-header">
        <h2 class="text-sm font-semibold">Default dataset</h2>
      </div>
      <div class="p-4">
        <.field_label kind={:scenario} field_path={["default_dataset"]}>Dataset</.field_label>
        <.live_component
          module={MaestroWeb.Components.ReferencePicker}
          id="default-dataset-picker"
          workspace={@workspace}
          kind={:dataset}
          path={["default_dataset"]}
          value={@data["default_dataset"] || ""}
        />
      </div>
    </section>

    <section class="panel p-4">
      <.step_list
        workspace={@workspace}
        steps={@data["steps"] || []}
        testcase_index={nil}
        client_names={@client_names}
        expected_raw={@expected_raw}
      />

      <p :if={msg = Form.error_for(@errors, "#/steps")} class="mt-2 text-sm text-error">{msg}</p>
    </section>
    """
  end

  @doc "Suite body: an ordered list of testcases, each with their own name/description/steps."
  attr :workspace, :any, required: true
  attr :data, :map, required: true
  attr :client_names, :list, required: true
  attr :expected_raw, :map, required: true
  attr :errors, :list, required: true

  def suite_fields(assigns) do
    ~H"""
    <div class="flex items-center justify-between">
      <h2 class="text-sm font-semibold">
        Testcases
        <span class="ml-1 font-normal text-base-content/50">
          {length(@data["testcases"] || [])}
        </span>
      </h2>
      <.button phx-click="suite-add-testcase">
        <.icon name="hero-plus-mini" class="size-4" /> Add testcase
      </.button>
    </div>

    <section
      :for={{testcase, tc_index} <- Enum.with_index(@data["testcases"] || [])}
      class="panel"
    >
      <div class="panel-header">
        <span class="flex items-center gap-2">
          <span class="grid size-6 place-items-center rounded-md bg-primary/10 text-xs font-semibold text-primary">
            {tc_index + 1}
          </span>
          <span class="font-mono text-xs text-base-content/50">testcase #{tc_index + 1}</span>
        </span>
        <.button
          variant="ghost"
          size="xs"
          class="text-base-content/50 hover:text-error"
          phx-click="suite-remove-testcase"
          phx-value-index={tc_index}
        >
          <.icon name="hero-trash-mini" class="size-3.5" /> Remove testcase
        </.button>
      </div>

      <div class="space-y-4 p-4">
        <div class="grid gap-x-4 sm:grid-cols-2">
          <div class="fieldset">
            <span class="label mb-1.5 text-xs font-medium text-base-content/80">Id</span>
            <input
              type="text"
              value={testcase["id"]}
              phx-change="suite-update-testcase-field"
              name={"testcases[#{tc_index}][id]"}
              placeholder="e.g. login-succeeds"
              class="w-full input font-mono text-[0.8125rem]"
            />
          </div>

          <div class="fieldset">
            <span class="label mb-1.5 text-xs font-medium text-base-content/80">Name</span>
            <input
              type="text"
              value={testcase["name"]}
              phx-change="suite-update-testcase-field"
              name={"testcases[#{tc_index}][name]"}
              class="w-full input"
            />
          </div>
        </div>

        <.step_list
          workspace={@workspace}
          steps={testcase["steps"] || []}
          testcase_index={tc_index}
          client_names={@client_names}
          expected_raw={@expected_raw}
        />

        <p
          :if={msg = Form.error_for(@errors, "#/testcases/#{tc_index}")}
          class="text-sm text-error"
        >
          {msg}
        </p>
      </div>
    </section>

    <div
      :if={(@data["testcases"] || []) == []}
      class="rounded-box border border-dashed border-base-300 px-6 py-10 text-center text-sm text-base-content/60"
    >
      No testcases yet.
    </div>
    """
  end

  @doc """
  One step list (either a scenario's own `steps`, or one suite testcase's
  `steps`) `testcase_index` is `nil` for a scenario's steps, or the
  owning testcase's index for a suite. Every step field addresses itself
  via `name="steps[<tc>][<step>][field]"`, where `<tc>` is `"_"` for a
  scenario's own steps (`step_tc/1` picks that sentinel); every step
  button (add/remove/move/toggle) keeps using
  `phx-value-testcase_index={@testcase_index}` instead, since `phx-click`
  bindings do faithfully deliver `phx-value-*`.
  """
  attr :workspace, :any, required: true
  attr :steps, :list, required: true
  attr :testcase_index, :any, default: nil
  attr :client_names, :list, required: true
  attr :expected_raw, :map, required: true

  def step_list(assigns) do
    ~H"""
    <div>
      <div class="mb-2 flex flex-wrap items-center justify-between gap-2">
        <span class="section-label">Steps · {length(@steps)}</span>
        <div class="flex gap-2">
          <.button
            phx-click="step-add-template"
            phx-value-testcase_index={@testcase_index}
          >
            <.icon name="hero-plus-mini" class="size-4" /> Add step
          </.button>
          <.button
            phx-click="step-add-scenario-call"
            phx-value-testcase_index={@testcase_index}
          >
            <.icon name="hero-queue-list-mini" class="size-4" /> Add scenario call
          </.button>
        </div>
      </div>

      <.step_form
        :for={{step, step_index} <- Enum.with_index(@steps)}
        workspace={@workspace}
        step={step}
        step_index={step_index}
        step_count={length(@steps)}
        testcase_index={@testcase_index}
        client_names={@client_names}
        expected_raw={@expected_raw}
      />

      <p
        :if={@steps == []}
        class="rounded-field border border-dashed border-base-300 px-4 py-5 text-center text-sm text-base-content/60"
      >
        No steps yet.
      </p>
    </div>
    """
  end

  @doc "One step's editable form: template-step vs scenario-call toggle, its fields, and its asserts."
  attr :workspace, :any, required: true
  attr :step, :map, required: true
  attr :step_index, :integer, required: true
  attr :step_count, :integer, required: true
  attr :testcase_index, :any, default: nil
  attr :client_names, :list, required: true
  attr :expected_raw, :map, required: true

  def step_form(assigns) do
    assigns = assign(assigns, :tc, step_tc(assigns.testcase_index))

    ~H"""
    <div class="mb-2 overflow-hidden rounded-field border border-base-300 bg-base-100">
      <div class="flex flex-wrap items-center gap-2 border-b border-base-300 bg-base-200/50 px-3 py-2">
        <span class={[
          "grid size-6 shrink-0 place-items-center rounded-full border text-[0.6875rem] font-semibold",
          if(Map.has_key?(@step, "scenario"),
            do: "border-accent/30 bg-accent/10 text-accent",
            else: "border-base-300 bg-base-100 text-base-content/60"
          )
        ]}>
          {@step_index + 1}
        </span>

        <input
          type="text"
          value={@step["name"]}
          placeholder="Step name (optional)"
          phx-change="step-update-field"
          name={"steps[#{@tc}][#{@step_index}][name]"}
          class="input input-sm min-w-40 flex-1"
        />

        <span class="text-xs text-base-content/50">
          {if Map.has_key?(@step, "scenario"), do: "Scenario call", else: "Template step"}
        </span>

        <div class="flex items-center">
          <.button
            variant="ghost"
            class="btn-square"
            phx-click="step-move-up"
            phx-value-testcase_index={@testcase_index}
            phx-value-step_index={@step_index}
            disabled={@step_index == 0}
            aria-label="Move step up"
          >
            <.icon name="hero-arrow-up-mini" class="size-4" />
          </.button>
          <.button
            variant="ghost"
            class="btn-square"
            phx-click="step-move-down"
            phx-value-testcase_index={@testcase_index}
            phx-value-step_index={@step_index}
            disabled={@step_index == @step_count - 1}
            aria-label="Move step down"
          >
            <.icon name="hero-arrow-down-mini" class="size-4" />
          </.button>
          <.button
            variant="ghost"
            class="text-xs"
            phx-click="step-toggle-kind"
            phx-value-testcase_index={@testcase_index}
            phx-value-step_index={@step_index}
            title="Change step type"
          >
            <.icon name="hero-arrows-right-left-mini" class="size-4" />
            Switch to {if Map.has_key?(@step, "scenario"), do: "template step", else: "scenario call"}
          </.button>
          <.button
            variant="ghost"
            class="btn-square text-base-content/40 hover:text-error"
            phx-click="step-remove"
            phx-value-testcase_index={@testcase_index}
            phx-value-step_index={@step_index}
            aria-label="Remove step"
          >
            <.icon name="hero-trash-mini" class="size-4" />
          </.button>
        </div>
      </div>

      <div class="space-y-3 p-3">
        <div :if={Map.has_key?(@step, "scenario")} class="grid gap-x-4 gap-y-3 md:grid-cols-2">
          <div>
            <span class="label mb-1.5 text-xs font-medium text-base-content/80">Scenario</span>
            <.live_component
              module={MaestroWeb.Components.ReferencePicker}
              id={"scenario-picker-#{@tc}-#{@step_index}"}
              workspace={@workspace}
              kind={:scenario}
              path={step_path(@testcase_index, @step_index, "scenario")}
              value={@step["scenario"]}
            />
          </div>
          <div>
            <span class="label mb-1.5 text-xs font-medium text-base-content/80">Dataset (optional)</span>
            <.live_component
              module={MaestroWeb.Components.ReferencePicker}
              id={"scenario-call-dataset-picker-#{@tc}-#{@step_index}"}
              workspace={@workspace}
              kind={:dataset}
              path={step_path(@testcase_index, @step_index, "dataset")}
              value={@step["dataset"] || ""}
            />
          </div>
        </div>

        <div :if={!Map.has_key?(@step, "scenario")} class="grid gap-x-4 gap-y-3 md:grid-cols-2">
          <div>
            <span class="label mb-1.5 text-xs font-medium text-base-content/80">Client</span>
            <select
              phx-change="step-update-field"
              name={"steps[#{@tc}][#{@step_index}][client]"}
              class="select select-sm w-full font-mono"
            >
              <option value="">(choose a client)</option>
              <option
                :for={client <- @client_names}
                value={client}
                selected={client == @step["client"]}
              >
                {client}
              </option>
            </select>
          </div>

          <div>
            <span class="label mb-1.5 text-xs font-medium text-base-content/80">Template</span>
            <.live_component
              module={MaestroWeb.Components.ReferencePicker}
              id={"template-picker-#{@tc}-#{@step_index}"}
              workspace={@workspace}
              kind={:template}
              path={step_path(@testcase_index, @step_index, "template")}
              value={@step["template"] || ""}
            />
          </div>

          <div :if={!is_nil(@testcase_index)} class="md:col-span-2">
            <span class="label mb-1.5 text-xs font-medium text-base-content/80">Dataset</span>
            <.live_component
              module={MaestroWeb.Components.ReferencePicker}
              id={"dataset-picker-#{@tc}-#{@step_index}"}
              workspace={@workspace}
              kind={:dataset}
              path={step_path(@testcase_index, @step_index, "dataset")}
              value={@step["dataset"] || ""}
            />
          </div>
          <p :if={is_nil(@testcase_index)} class="text-xs text-base-content/60 md:col-span-2">
            A scenario's steps render against the scenario's single resolved dataset there's no
            per-step dataset here (unlike a suite's steps).
          </p>
        </div>

        <.assert_list
          asserts={@step["assert"] || []}
          testcase_index={@testcase_index}
          step_index={@step_index}
          expected_raw={@expected_raw}
        />
      </div>
    </div>
    """
  end

  defp step_path(nil, step_index, field), do: ["steps", step_index, field]

  defp step_path(testcase_index, step_index, field),
    do: ["testcases", testcase_index, "steps", step_index, field]

  # The `<tc>` segment used in a step field's bracket-notation `name`: `"_"`
  # for a scenario's own steps (no testcase nesting), or the testcase's
  # index as a string for a suite. Kept distinct from `step_path/3`'s
  # `nil`/integer shape, which addresses `@data` directly via `Access` and
  # has no reason to use the same sentinel.
  defp step_tc(nil), do: "_"
  defp step_tc(testcase_index), do: to_string(testcase_index)

  @doc "One step's list of assertion checks (matcher/path/expected)."
  attr :asserts, :list, required: true
  attr :testcase_index, :any, default: nil
  attr :step_index, :integer, required: true
  attr :expected_raw, :map, required: true

  def assert_list(assigns) do
    assigns = assign(assigns, :tc, step_tc(assigns.testcase_index))

    ~H"""
    <div class="border-t border-base-300 pt-3">
      <div class="mb-2 flex items-center justify-between">
        <span class="section-label">Asserts · {length(@asserts)}</span>
        <.button
          size="xs"
          phx-click="assert-add"
          phx-value-testcase_index={@testcase_index}
          phx-value-step_index={@step_index}
        >
          <.icon name="hero-plus-mini" class="size-3.5" /> Add assert
        </.button>
      </div>

      <div
        :for={{assert, assert_index} <- Enum.with_index(@asserts)}
        class="mb-2 rounded-field border border-base-300 bg-base-200/50 p-2.5"
      >
        <div class="mb-2 flex gap-2">
          <input
            type="text"
            value={assert["matcher"] || "json_match"}
            placeholder="matcher"
            phx-change="assert-update-field"
            name={"asserts[#{@tc}][#{@step_index}][#{assert_index}][matcher]"}
            class="input input-sm flex-1 font-mono"
          />
          <input
            type="text"
            value={assert["path"]}
            placeholder="path (e.g. $.total)"
            phx-change="assert-update-field"
            name={"asserts[#{@tc}][#{@step_index}][#{assert_index}][path]"}
            class="input input-sm flex-1 font-mono"
          />
          <.button
            variant="ghost"
            class="btn-square text-base-content/40 hover:text-error"
            phx-click="assert-remove"
            phx-value-testcase_index={@testcase_index}
            phx-value-step_index={@step_index}
            phx-value-assert_index={assert_index}
            aria-label="Remove assert"
          >
            <.icon name="hero-trash-mini" class="size-4" />
          </.button>
        </div>

        <% {raw, error} =
          Form.expected_display(
            @expected_raw,
            @testcase_index,
            @step_index,
            assert_index,
            assert["expected"]
          ) %>
        <span class="label mb-1 text-[0.6875rem] font-medium text-base-content/60">
          Expected (JSON)
        </span>
        <textarea
          phx-change="assert-update-expected"
          name={"asserts[#{@tc}][#{@step_index}][#{assert_index}][expected]"}
          class={["w-full textarea textarea-sm font-mono", error && "textarea-error"]}
          rows="2"
        >{raw}</textarea>
        <p :if={error} class="mt-1 flex gap-2 items-center text-sm text-error">
          <.icon name="hero-exclamation-circle" class="size-4" />{error}
        </p>
      </div>

      <p :if={@asserts == []} class="text-xs text-base-content/50">No asserts yet.</p>
    </div>
    """
  end

  @doc "Test plan body: searchable multi-select over the workspace's existing suites."
  attr :data, :map, required: true
  attr :suite_entries, :list, required: true

  def test_plan_fields(assigns) do
    ~H"""
    <div>
      <div class="px-2 pt-1">
        <.field_label kind={:test_plan} field_path={["test_suites"]}>
          Suites in this plan
        </.field_label>
      </div>

      <div class="flex max-h-96 flex-col gap-0.5 overflow-y-auto">
        <label
          :for={entry <- @suite_entries}
          class={[
            "flex cursor-pointer items-center gap-3 rounded-field px-2 py-2 transition-colors",
            if(entry.path in (@data["test_suites"] || []),
              do: "bg-primary/5 hover:bg-primary/10",
              else: "hover:bg-base-200"
            )
          ]}
        >
          <input
            type="checkbox"
            checked={entry.path in (@data["test_suites"] || [])}
            phx-click="test-plan-toggle-suite"
            phx-value-path={entry.path}
            class="checkbox checkbox-sm checkbox-primary"
          />
          <span class="font-mono text-[0.8125rem]">{entry.path}</span>
          <span :if={entry.name} class="truncate text-sm text-base-content/50">{entry.name}</span>
        </label>
      </div>

      <p :if={@suite_entries == []} class="px-2 py-4 text-sm text-base-content/60">
        No suites in this workspace yet.
      </p>
    </div>
    """
  end
end
