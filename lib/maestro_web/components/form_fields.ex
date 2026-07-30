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
        class="w-full input"
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
    <div class="mb-4">
      <div class="join">
        <button
          type="button"
          class={["join-item btn btn-sm", @dataset_mode == "data" && "btn-active"]}
          phx-click="dataset-set-mode"
          phx-value-mode="data"
        >
          Single value
        </button>
        <button
          type="button"
          class={["join-item btn btn-sm", @dataset_mode == "rows" && "btn-active"]}
          phx-click="dataset-set-mode"
          phx-value-mode="rows"
        >
          Table of rows
        </button>
      </div>
      <p class="mt-1 text-sm text-base-content/70">
        <span :if={@dataset_mode == "data"}>
          One fixed set of key/value pairs, used as-is wherever this dataset is referenced.
        </span>
        <span :if={@dataset_mode == "rows"}>
          A table of rows with shared columns a step or scenario using this dataset runs once
          per row.
        </span>
      </p>
    </div>

    <div :if={@dataset_mode == "data"} class="mb-6">
      <div class="flex items-center justify-between mb-1">
        <.field_label kind={:dataset} field_path={["data"]}>Data</.field_label>
        <.button phx-click="dataset-add-data-field">Add field</.button>
      </div>

      <div :for={{{key, value}, index} <- Enum.with_index(@data_pairs)} class="flex gap-2 mb-2">
        <input
          type="text"
          value={key}
          placeholder="key"
          phx-change="dataset-update-data-field-key"
          name={"data_pairs[#{index}][key]"}
          class="input flex-1 font-mono"
        />
        <input
          type="text"
          value={value}
          placeholder="value"
          phx-change="dataset-update-data-field-value"
          name={"data_pairs[#{index}][value]"}
          class="input flex-1"
        />
        <.button phx-click="dataset-remove-data-field" phx-value-index={index}>
          <.icon name="hero-x-mark" />
        </.button>
      </div>

      <p :if={@data_pairs == []} class="text-sm text-base-content/70">
        No fields yet. Click "Add field" to add a key/value pair (e.g.
        <span class="font-mono">username</span>
        / <span class="font-mono">alice</span>).
      </p>
    </div>

    <div :if={@dataset_mode == "rows"}>
      <div class="flex items-center justify-between mb-1">
        <.field_label kind={:dataset} field_path={["rows"]}>Rows</.field_label>
        <div class="flex gap-2">
          <.button phx-click="dataset-add-column">Add column</.button>
          <.button phx-click="dataset-add-row" disabled={@row_columns == []}>Add row</.button>
        </div>
      </div>

      <div :if={@row_columns != []} class="overflow-x-auto">
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
                  <.button phx-click="dataset-remove-column" phx-value-index={col_index}>
                    <.icon name="hero-x-mark" class="size-3" />
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
                <.button phx-click="dataset-remove-row" phx-value-index={row_index}>
                  <.icon name="hero-x-mark" class="size-3" />
                </.button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p :if={@row_columns == []} class="text-sm text-base-content/70">
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
      <div class="flex flex-wrap gap-2 mt-1">
        <label :for={client <- @client_names} class="label cursor-pointer gap-1">
          <input
            type="checkbox"
            checked={client in (@data["clients"] || [])}
            phx-click="template-toggle-client"
            phx-value-client={client}
            class="checkbox checkbox-sm"
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
        class={["w-full textarea font-mono", @payload_error && "textarea-error"]}
        rows="8"
      >{@payload_raw}</textarea>
      <p :if={@payload_error} class="mt-1.5 flex gap-2 items-center text-sm text-error">
        <.icon name="hero-exclamation-circle" class="size-5" />{@payload_error}
      </p>
    </div>

    <div class="fieldset mb-2">
      <.field_label kind={:template} field_path={["options"]}>Options (JSON)</.field_label>
      <textarea
        phx-change="template-update-options"
        name="options"
        class={["w-full textarea font-mono", @options_error && "textarea-error"]}
        rows="6"
      >{@options_raw}</textarea>
      <p :if={@options_error} class="mt-1.5 flex gap-2 items-center text-sm text-error">
        <.icon name="hero-exclamation-circle" class="size-5" />{@options_error}
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
    <div class="fieldset mb-4">
      <.field_label kind={:scenario} field_path={["default_dataset"]}>Default dataset</.field_label>
      <.live_component
        module={MaestroWeb.Components.ReferencePicker}
        id="default-dataset-picker"
        workspace={@workspace}
        kind={:dataset}
        path={["default_dataset"]}
        value={@data["default_dataset"] || ""}
      />
    </div>

    <.step_list
      workspace={@workspace}
      steps={@data["steps"] || []}
      testcase_index={nil}
      client_names={@client_names}
      expected_raw={@expected_raw}
    />

    <p :if={msg = Form.error_for(@errors, "#/steps")} class="mt-2 text-sm text-error">{msg}</p>
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
    <div class="flex items-center justify-between mb-2">
      <h3 class="font-semibold">Testcases</h3>
      <.button phx-click="suite-add-testcase">Add testcase</.button>
    </div>

    <div
      :for={{testcase, tc_index} <- Enum.with_index(@data["testcases"] || [])}
      class="card bg-base-200 p-4 mb-4"
    >
      <div class="flex items-center justify-between mb-2">
        <span class="font-mono text-xs text-base-content/50">testcase #{tc_index + 1}</span>
        <.button phx-click="suite-remove-testcase" phx-value-index={tc_index}>
          <.icon name="hero-x-mark" class="size-3.5" /> Remove testcase
        </.button>
      </div>

      <div class="fieldset mb-2">
        <span class="label mb-1">Id</span>
        <input
          type="text"
          value={testcase["id"]}
          phx-change="suite-update-testcase-field"
          name={"testcases[#{tc_index}][id]"}
          class="w-full input"
        />
      </div>

      <div class="fieldset mb-2">
        <span class="label mb-1">Name</span>
        <input
          type="text"
          value={testcase["name"]}
          phx-change="suite-update-testcase-field"
          name={"testcases[#{tc_index}][name]"}
          class="w-full input"
        />
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
        class="mt-2 text-sm text-error"
      >
        {msg}
      </p>
    </div>

    <p :if={(@data["testcases"] || []) == []} class="text-sm text-base-content/70">
      No testcases yet.
    </p>
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
      <div class="flex items-center justify-between mb-1">
        <span class="label">Steps</span>
        <div class="flex gap-2">
          <.button
            phx-click="step-add-template"
            phx-value-testcase_index={@testcase_index}
          >
            Add step
          </.button>
          <.button
            phx-click="step-add-scenario-call"
            phx-value-testcase_index={@testcase_index}
          >
            Add scenario call
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

      <p :if={@steps == []} class="text-sm text-base-content/70">No steps yet.</p>
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
    <div class="card bg-base-100 border border-base-300 p-3 mb-2">
      <div class="flex items-center gap-2 mb-2">
        <span class="font-mono text-xs text-base-content/50">#{@step_index + 1}</span>

        <input
          type="text"
          value={@step["name"]}
          placeholder="name (optional)"
          phx-change="step-update-field"
          name={"steps[#{@tc}][#{@step_index}][name]"}
          class="input input-sm flex-1"
        />

        <.button
          phx-click="step-move-up"
          phx-value-testcase_index={@testcase_index}
          phx-value-step_index={@step_index}
          disabled={@step_index == 0}
        >
          <.icon name="hero-chevron-up" class="size-3.5" />
        </.button>
        <.button
          phx-click="step-move-down"
          phx-value-testcase_index={@testcase_index}
          phx-value-step_index={@step_index}
          disabled={@step_index == @step_count - 1}
        >
          <.icon name="hero-chevron-down" class="size-3.5" />
        </.button>
        <.button
          phx-click="step-toggle-kind"
          phx-value-testcase_index={@testcase_index}
          phx-value-step_index={@step_index}
        >
          Switch to {if Map.has_key?(@step, "scenario"), do: "template step", else: "scenario call"}
        </.button>
        <.button
          phx-click="step-remove"
          phx-value-testcase_index={@testcase_index}
          phx-value-step_index={@step_index}
        >
          <.icon name="hero-x-mark" class="size-3.5" />
        </.button>
      </div>

      <div :if={Map.has_key?(@step, "scenario")} class="mb-2">
        <span class="label mb-1">Scenario</span>
        <.live_component
          module={MaestroWeb.Components.ReferencePicker}
          id={"scenario-picker-#{@tc}-#{@step_index}"}
          workspace={@workspace}
          kind={:scenario}
          path={step_path(@testcase_index, @step_index, "scenario")}
          value={@step["scenario"]}
        />

        <span class="label mb-1 mt-2">Dataset (optional)</span>
        <.live_component
          module={MaestroWeb.Components.ReferencePicker}
          id={"scenario-call-dataset-picker-#{@tc}-#{@step_index}"}
          workspace={@workspace}
          kind={:dataset}
          path={step_path(@testcase_index, @step_index, "dataset")}
          value={@step["dataset"] || ""}
        />
      </div>

      <div :if={!Map.has_key?(@step, "scenario")} class="mb-2">
        <span class="label mb-1">Client</span>
        <select
          phx-change="step-update-field"
          name={"steps[#{@tc}][#{@step_index}][client]"}
          class="select select-sm w-full mb-2"
        >
          <option value="">(choose a client)</option>
          <option :for={client <- @client_names} value={client} selected={client == @step["client"]}>
            {client}
          </option>
        </select>

        <span class="label mb-1">Template</span>
        <.live_component
          module={MaestroWeb.Components.ReferencePicker}
          id={"template-picker-#{@tc}-#{@step_index}"}
          workspace={@workspace}
          kind={:template}
          path={step_path(@testcase_index, @step_index, "template")}
          value={@step["template"] || ""}
        />

        <div :if={!is_nil(@testcase_index)}>
          <span class="label mb-1 mt-2">Dataset</span>
          <.live_component
            module={MaestroWeb.Components.ReferencePicker}
            id={"dataset-picker-#{@tc}-#{@step_index}"}
            workspace={@workspace}
            kind={:dataset}
            path={step_path(@testcase_index, @step_index, "dataset")}
            value={@step["dataset"] || ""}
          />
        </div>
        <p :if={is_nil(@testcase_index)} class="text-xs text-base-content/70 mt-2">
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
    <div class="mt-2">
      <div class="flex items-center justify-between mb-1">
        <span class="label">Asserts</span>
        <.button
          phx-click="assert-add"
          phx-value-testcase_index={@testcase_index}
          phx-value-step_index={@step_index}
        >
          Add assert
        </.button>
      </div>

      <div
        :for={{assert, assert_index} <- Enum.with_index(@asserts)}
        class="bg-base-200 rounded p-2 mb-1"
      >
        <div class="flex gap-2 mb-1">
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
            phx-click="assert-remove"
            phx-value-testcase_index={@testcase_index}
            phx-value-step_index={@step_index}
            phx-value-assert_index={assert_index}
          >
            <.icon name="hero-x-mark" class="size-3.5" />
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
        <span class="label text-xs mb-1">Expected (JSON)</span>
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

      <p :if={@asserts == []} class="text-sm text-base-content/70">No asserts yet.</p>
    </div>
    """
  end

  @doc "Test plan body: searchable multi-select over the workspace's existing suites."
  attr :data, :map, required: true
  attr :suite_entries, :list, required: true

  def test_plan_fields(assigns) do
    ~H"""
    <div>
      <.field_label kind={:test_plan} field_path={["test_suites"]}>Suites</.field_label>

      <div class="flex flex-col gap-1 mt-1">
        <label :for={entry <- @suite_entries} class="label cursor-pointer justify-start gap-2">
          <input
            type="checkbox"
            checked={entry.path in (@data["test_suites"] || [])}
            phx-click="test-plan-toggle-suite"
            phx-value-path={entry.path}
            class="checkbox checkbox-sm"
          />
          <span class="font-mono text-sm">{entry.path}</span>
          <span :if={entry.name} class="text-sm text-base-content/70">({entry.name})</span>
        </label>
      </div>

      <p :if={@suite_entries == []} class="text-sm text-base-content/70 mt-1">
        No suites in this workspace yet.
      </p>
    </div>
    """
  end
end
