defmodule MaestroWeb.WorkspaceLive.Form do
  @moduledoc """
  Single LiveView for creating/editing every resource kind, dispatching on
  `@kind` (from the route's `:kind` segment).

  Routed at `/:kind/new` and `/:kind/edit/*path` (see `MaestroWeb.Router`),
  matched before the show page's `/:kind/*path` catch-all. This makes
  `"new"` and `"edit"` (or, for edit, any path starting with `"edit/"`)
  reserved resource path segments within a kind a resource actually named
  `new`, or `edit`, is unreachable via its own show page, since those two
  routes win the match first. `Maestro.Resources` itself has no such
  restriction (it'll happily write/fetch a file literally named
  `new.json`) this is purely a web-routing collision, not a filesystem or
  schema one.

  The editable resource is kept as a plain nested map/list in `@data`,
  matching exactly the JSON shape `Maestro.Resources.write/4` expects.
  Validation happens on submit by assembling `@data` and calling
  `Maestro.Resources.write/4`, never before every field could be half-typed
  input mid-edit is expected and not an error.
  `Maestro.Resources.Schemas`' `ExJsonSchema` validation errors are
  `{message, json_pointer_path}` pairs; `error_for/2` maps them back to a
  specific field by that path, the same convention `Resolver`'s own error
  enrichment already uses.
  """

  use MaestroWeb, :live_view

  import MaestroWeb.Components.FormFields

  alias Maestro.Client
  alias Maestro.Resources
  alias MaestroWeb.ResourceComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"kind" => segment} = params, _uri, socket) do
    workspace = socket.assigns.workspace

    case ResourceComponents.kind_for_segment(segment) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Unknown resource kind #{inspect(segment)}.")
         |> push_navigate(to: "/workspace/#{workspace.id}")}

      kind ->
        socket =
          socket
          |> assign(:kind, kind)
          |> assign(:segment, segment)
          |> assign(:current_kind, kind)

        {:noreply, apply_action(socket, socket.assigns.live_action, params)}
    end
  end

  @impl true
  def handle_info({:reference_picker, data_path, action}, socket) do
    {:noreply,
     update(socket, :data, fn data ->
       case action do
         {:select, entry_path} -> put_at_path(data, data_path, entry_path)
         :clear -> put_at_path(data, data_path, "")
         :use_inline -> put_at_path(data, data_path, %{})
       end
     end)}
  end

  @impl true
  def handle_event("update-path", %{"path" => path}, socket) do
    {:noreply, assign(socket, :path_input, path)}
  end

  def handle_event("update-id", %{"resource_id" => id}, socket) do
    {:noreply, update(socket, :data, &put_or_drop(&1, "id", id))}
  end

  def handle_event("update-name", %{"name" => name}, socket) do
    {:noreply, update(socket, :data, &put_or_drop(&1, "name", name))}
  end

  def handle_event("update-description", %{"description" => description}, socket) do
    {:noreply, update(socket, :data, &put_or_drop(&1, "description", description))}
  end

  def handle_event("save", _params, socket) do
    workspace = socket.assigns.workspace
    kind = socket.assigns.kind
    path = String.trim(socket.assigns.path_input)

    cond do
      path == "" ->
        {:noreply, assign(socket, :path_error, "Path can't be blank.")}

      socket.assigns.live_action == :new and
          match?({:ok, _}, Resources.fetch(workspace, kind, path)) ->
        {:noreply, assign(socket, :path_error, "A #{kind} already exists at this path.")}

      true ->
        case Resources.write(workspace, kind, path, prepare_for_save(kind, socket.assigns.data)) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:info, "Saved #{path}.")
             |> push_navigate(to: "/workspace/#{workspace.id}/#{socket.assigns.segment}/#{path}")}

          {:error, {:invalid, reasons}} ->
            {:noreply, assign(socket, :errors, reasons)}

          {:error, :not_found} ->
            {:noreply, assign(socket, :path_error, "Invalid path.")}
        end
    end
  end

  def handle_event("dataset-set-mode", %{"mode" => mode}, socket) when mode in ["data", "rows"] do
    other = if mode == "data", do: "rows", else: "data"

    socket =
      socket
      |> assign(:dataset_mode, mode)
      |> update(:data, &Map.delete(&1, other))

    socket =
      case mode do
        "data" -> assign(socket, :row_columns, [])
        "rows" -> assign(socket, :data_pairs, [])
      end

    {:noreply, socket}
  end

  def handle_event("dataset-add-data-field", _params, socket) do
    {:noreply, socket |> update(:data_pairs, &(&1 ++ [{"", ""}])) |> sync_data_pairs()}
  end

  def handle_event("dataset-remove-data-field", %{"index" => index}, socket) do
    index = String.to_integer(index)
    {:noreply, socket |> update(:data_pairs, &List.delete_at(&1, index)) |> sync_data_pairs()}
  end

  def handle_event("dataset-update-data-field-key", %{"data_pairs" => pairs_params}, socket) do
    [{index, %{"key" => key}}] = Map.to_list(pairs_params)
    index = String.to_integer(index)

    {:noreply,
     socket
     |> update(:data_pairs, fn pairs ->
       List.update_at(pairs, index, fn {_old_key, value} -> {key, value} end)
     end)
     |> sync_data_pairs()}
  end

  def handle_event("dataset-update-data-field-value", %{"data_pairs" => pairs_params}, socket) do
    [{index, %{"value" => value}}] = Map.to_list(pairs_params)
    index = String.to_integer(index)

    {:noreply,
     socket
     |> update(:data_pairs, fn pairs ->
       List.update_at(pairs, index, fn {key, _old_value} -> {key, value} end)
     end)
     |> sync_data_pairs()}
  end

  def handle_event("dataset-add-column", _params, socket) do
    {:noreply, socket |> update(:row_columns, &(&1 ++ [""])) |> pad_rows_to_columns()}
  end

  def handle_event("dataset-rename-column", %{"row_columns" => columns_params}, socket) do
    [{index, name}] = Map.to_list(columns_params)
    index = String.to_integer(index)
    old_name = Enum.at(socket.assigns.row_columns, index)

    socket =
      socket
      |> update(:row_columns, &List.replace_at(&1, index, name))
      |> update(:data, fn data ->
        Map.update(data, "rows", [], fn rows ->
          Enum.map(rows, fn row ->
            {value, row} = Map.pop(row, old_name, "")
            Map.put(row, name, value)
          end)
        end)
      end)

    {:noreply, socket}
  end

  def handle_event("dataset-remove-column", %{"index" => index}, socket) do
    index = String.to_integer(index)
    name = Enum.at(socket.assigns.row_columns, index)

    socket =
      socket
      |> update(:row_columns, &List.delete_at(&1, index))
      |> update(:data, fn data ->
        Map.update(data, "rows", [], fn rows -> Enum.map(rows, &Map.delete(&1, name)) end)
      end)

    {:noreply, socket}
  end

  def handle_event("dataset-add-row", _params, socket) do
    blank_row = Map.new(socket.assigns.row_columns, &{&1, ""})

    {:noreply,
     update(
       socket,
       :data,
       &Map.update(&1, "rows", [blank_row], fn rows -> rows ++ [blank_row] end)
     )}
  end

  def handle_event("dataset-remove-row", %{"index" => index}, socket) do
    index = String.to_integer(index)

    {:noreply,
     update(
       socket,
       :data,
       &Map.update(&1, "rows", [], fn rows -> List.delete_at(rows, index) end)
     )}
  end

  def handle_event("dataset-update-row-field", %{"rows" => rows_params}, socket) do
    {:noreply,
     update(socket, :data, fn data ->
       Map.update(data, "rows", [], fn rows ->
         Enum.reduce(rows_params, rows, fn {index, fields}, acc ->
           List.update_at(acc, String.to_integer(index), &Map.merge(&1, fields))
         end)
       end)
     end)}
  end

  def handle_event("template-toggle-client", %{"client" => client}, socket) do
    clients = socket.assigns.data["clients"] || []
    clients = if client in clients, do: List.delete(clients, client), else: clients ++ [client]
    {:noreply, update(socket, :data, &Map.put(&1, "clients", clients))}
  end

  def handle_event("template-update-payload", %{"payload" => raw}, socket) do
    {:noreply, update_json_field(socket, "payload", raw)}
  end

  def handle_event("template-update-options", %{"options" => raw}, socket) do
    {:noreply, update_json_field(socket, "options", raw)}
  end

  def handle_event("test-plan-toggle-suite", %{"path" => suite_path}, socket) do
    suites = socket.assigns.data["test_suites"] || []

    suites =
      if suite_path in suites, do: List.delete(suites, suite_path), else: suites ++ [suite_path]

    {:noreply, update(socket, :data, &Map.put(&1, "test_suites", suites))}
  end

  def handle_event("suite-add-testcase", _params, socket) do
    testcase = %{"id" => "", "steps" => []}

    {:noreply,
     update(
       socket,
       :data,
       &Map.update(&1, "testcases", [testcase], fn tcs -> tcs ++ [testcase] end)
     )}
  end

  def handle_event("suite-remove-testcase", %{"index" => index}, socket) do
    index = String.to_integer(index)

    {:noreply,
     update(
       socket,
       :data,
       &Map.update(&1, "testcases", [], fn tcs -> List.delete_at(tcs, index) end)
     )}
  end

  def handle_event("suite-update-testcase-field", %{"testcases" => testcases_params}, socket) do
    {:noreply,
     update(socket, :data, fn data ->
       Map.update(data, "testcases", [], fn tcs ->
         Enum.reduce(testcases_params, tcs, fn {index, fields}, acc ->
           List.update_at(acc, String.to_integer(index), &Map.merge(&1, fields))
         end)
       end)
     end)}
  end

  def handle_event("step-add-template", params, socket) do
    step = %{"client" => "", "template" => "", "dataset" => ""}
    {:noreply, update_steps_by_click(socket, params, &(&1 ++ [step]))}
  end

  def handle_event("step-add-scenario-call", params, socket) do
    step = %{"scenario" => ""}
    {:noreply, update_steps_by_click(socket, params, &(&1 ++ [step]))}
  end

  def handle_event("step-remove", %{"step_index" => step_index} = params, socket) do
    step_index = String.to_integer(step_index)
    {:noreply, update_steps_by_click(socket, params, &List.delete_at(&1, step_index))}
  end

  def handle_event("step-move-up", %{"step_index" => step_index} = params, socket) do
    step_index = String.to_integer(step_index)
    {:noreply, update_steps_by_click(socket, params, &swap(&1, step_index, step_index - 1))}
  end

  def handle_event("step-move-down", %{"step_index" => step_index} = params, socket) do
    step_index = String.to_integer(step_index)
    {:noreply, update_steps_by_click(socket, params, &swap(&1, step_index, step_index + 1))}
  end

  def handle_event("step-toggle-kind", %{"step_index" => step_index} = params, socket) do
    step_index = String.to_integer(step_index)

    {:noreply,
     update_steps_by_click(socket, params, fn steps ->
       List.update_at(steps, step_index, fn
         %{"scenario" => _} -> %{"client" => "", "template" => "", "dataset" => ""}
         _template_step -> %{"scenario" => ""}
       end)
     end)}
  end

  def handle_event("step-update-field", %{"steps" => steps_params}, socket) do
    {:noreply,
     Enum.reduce(steps_params, socket, fn {tc, tc_steps}, acc ->
       Enum.reduce(tc_steps, acc, fn {step_index, fields}, acc2 ->
         update_steps(acc2, tc, fn steps ->
           List.update_at(steps, String.to_integer(step_index), &Map.merge(&1, fields))
         end)
       end)
     end)}
  end

  def handle_event("assert-add", %{"step_index" => step_index} = params, socket) do
    step_index = String.to_integer(step_index)
    entry = %{"matcher" => "json_match", "path" => "", "expected" => ""}

    {:noreply,
     update_steps_by_click(socket, params, fn steps ->
       List.update_at(steps, step_index, fn step ->
         Map.update(step, "assert", [entry], fn asserts -> asserts ++ [entry] end)
       end)
     end)}
  end

  def handle_event(
        "assert-remove",
        %{"step_index" => step_index, "assert_index" => assert_index} = params,
        socket
      ) do
    step_index = String.to_integer(step_index)
    assert_index = String.to_integer(assert_index)

    {:noreply,
     update_steps_by_click(socket, params, fn steps ->
       List.update_at(steps, step_index, fn step ->
         Map.update(step, "assert", [], &List.delete_at(&1, assert_index))
       end)
     end)}
  end

  def handle_event("assert-update-field", %{"asserts" => asserts_params}, socket) do
    {:noreply,
     Enum.reduce(asserts_params, socket, fn {tc, tc_steps}, acc ->
       Enum.reduce(tc_steps, acc, fn {step_index, step_asserts}, acc2 ->
         Enum.reduce(step_asserts, acc2, fn {assert_index, fields}, acc3 ->
           update_steps(acc3, tc, fn steps ->
             List.update_at(steps, String.to_integer(step_index), fn step ->
               Map.update(step, "assert", [], fn asserts ->
                 List.update_at(asserts, String.to_integer(assert_index), &Map.merge(&1, fields))
               end)
             end)
           end)
         end)
       end)
     end)}
  end

  def handle_event("assert-update-expected", %{"asserts" => asserts_params}, socket) do
    {tc, tc_steps} = Enum.at(asserts_params, 0)
    {step_index, step_asserts} = Enum.at(tc_steps, 0)
    {assert_index, %{"expected" => raw}} = Enum.at(step_asserts, 0)
    step_index = String.to_integer(step_index)
    assert_index = String.to_integer(assert_index)
    key = {tc, step_index, assert_index}

    case Jason.decode(raw) do
      {:ok, value} ->
        socket =
          update_steps(socket, tc, fn steps ->
            List.update_at(steps, step_index, fn step ->
              Map.update(step, "assert", [], fn asserts ->
                List.update_at(asserts, assert_index, &Map.put(&1, "expected", value))
              end)
            end)
          end)

        {:noreply, update(socket, :expected_raw, &Map.delete(&1, key))}

      {:error, _reason} ->
        {:noreply, update(socket, :expected_raw, &Map.put(&1, key, {raw, "Invalid JSON."}))}
    end
  end

  @doc "Maps an `ExJsonSchema` validation error to the field it's about, by JSON-pointer path."
  def error_for(errors, path_prefix) do
    Enum.find_value(errors, fn {message, path} ->
      String.starts_with?(path, path_prefix) && message
    end)
  end

  @doc """
  The `{raw_text, error_message}` to show for one assert entry's "expected"
  textarea: the last-typed-but-invalid text + error if the user is
  mid-editing an invalid value (see `@expected_raw`, populated by
  `assert-update-expected`'s error branch), otherwise the entry's real
  `"expected"` value pretty-printed with no error. `testcase_index` is
  `nil` for a scenario's own steps (no testcase nesting).
  """
  def expected_display(expected_raw, testcase_index, step_index, assert_index, real_value) do
    tc = if is_nil(testcase_index), do: "_", else: testcase_index

    case Map.get(expected_raw, {tc, step_index, assert_index}) do
      {raw, error} -> {raw, error}
      nil -> {Jason.encode!(real_value, pretty: true), nil}
    end
  end

  @doc """
  Where "Cancel" should navigate back to: the resource's own show page when
  editing an existing one, or the kind's index when creating a new one
  (there's no existing resource to go "back" to).
  """
  def cancel_path(workspace, segment, nil), do: "/workspace/#{workspace.id}/#{segment}"

  def cancel_path(workspace, segment, path), do: "/workspace/#{workspace.id}/#{segment}/#{path}"

  defp apply_action(socket, :new, _params) do
    kind = socket.assigns.kind

    socket
    |> assign(:page_title, "New #{ResourceComponents.kind_label(kind)}")
    |> assign(:path, nil)
    |> assign(:current_path, nil)
    |> assign(:path_input, "")
    |> assign(:path_error, nil)
    |> assign(:data, default_data(kind))
    |> assign(:errors, [])
    |> assign_kind_extras(kind)
    |> assign_editing_extras(kind)
  end

  defp apply_action(socket, :edit, %{"path" => path_segments}) do
    workspace = socket.assigns.workspace
    kind = socket.assigns.kind
    path = Enum.join(path_segments, "/")

    case Resources.fetch(workspace, kind, path) do
      {:ok, data} ->
        socket
        |> assign(:page_title, "Edit #{data["name"] || path}")
        |> assign(:path, path)
        |> assign(:current_path, path)
        |> assign(:path_input, path)
        |> assign(:path_error, nil)
        |> assign(:data, data)
        |> assign(:errors, [])
        |> assign_kind_extras(kind)
        |> assign_editing_extras(kind)

      {:error, reason} ->
        socket
        |> put_flash(:error, "Could not load #{path} for editing: #{inspect(reason)}")
        |> push_navigate(to: "/workspace/#{workspace.id}/#{socket.assigns.segment}")
    end
  end

  defp assign_kind_extras(socket, kind) when kind in [:template, :scenario, :suite] do
    assign(socket, :client_names, Client.Registry.names())
  end

  defp assign_kind_extras(socket, :test_plan) do
    assign(socket, :suite_entries, Resources.list(socket.assigns.workspace, :suite))
  end

  defp assign_kind_extras(socket, _kind), do: socket

  defp assign_editing_extras(socket, :dataset) do
    rows = Map.get(socket.assigns.data, "rows", [])
    columns = rows |> Enum.flat_map(&Map.keys/1) |> Enum.uniq()
    mode = if Map.has_key?(socket.assigns.data, "rows"), do: "rows", else: "data"

    socket
    |> assign(:dataset_mode, mode)
    |> assign(:data_pairs, Map.get(socket.assigns.data, "data", %{}) |> Map.to_list())
    |> assign(:row_columns, columns)
  end

  defp assign_editing_extras(socket, :template) do
    socket
    |> assign(
      :payload_raw,
      Jason.encode!(Map.get(socket.assigns.data, "payload", %{}), pretty: true)
    )
    |> assign(:payload_error, nil)
    |> assign(
      :options_raw,
      Jason.encode!(Map.get(socket.assigns.data, "options", %{}), pretty: true)
    )
    |> assign(:options_error, nil)
  end

  defp assign_editing_extras(socket, kind) when kind in [:scenario, :suite] do
    assign(socket, :expected_raw, %{})
  end

  defp assign_editing_extras(socket, _kind), do: socket

  defp default_data(:dataset), do: %{}
  defp default_data(:template), do: %{"clients" => [], "payload" => %{}}
  defp default_data(:test_plan), do: %{"id" => "", "test_suites" => []}
  defp default_data(:scenario), do: %{"steps" => []}
  defp default_data(:suite), do: %{"id" => "", "testcases" => []}

  defp sync_data_pairs(socket) do
    data_map = Map.new(socket.assigns.data_pairs)
    update(socket, :data, &put_or_drop(&1, "data", if(data_map == %{}, do: nil, else: data_map)))
  end

  defp pad_rows_to_columns(socket) do
    columns = socket.assigns.row_columns

    update(socket, :data, fn data ->
      Map.update(data, "rows", [], fn rows ->
        Enum.map(rows, fn row -> Map.new(columns, &{&1, Map.get(row, &1, "")}) end)
      end)
    end)
  end

  defp update_json_field(socket, field, raw) do
    case parse_json_field(raw) do
      {:ok, value} ->
        socket
        |> update(:data, &put_or_drop(&1, field, value))
        |> assign(:"#{field}_raw", raw)
        |> assign(:"#{field}_error", nil)

      {:error, message} ->
        socket |> assign(:"#{field}_raw", raw) |> assign(:"#{field}_error", message)
    end
  end

  defp parse_json_field(""), do: {:ok, nil}

  defp parse_json_field(raw) do
    case Jason.decode(raw) do
      {:ok, value} -> {:ok, value}
      {:error, _reason} -> {:error, "Invalid JSON."}
    end
  end

  defp put_or_drop(map, _key, nil), do: map
  defp put_or_drop(map, key, ""), do: Map.delete(map, key)
  defp put_or_drop(map, key, value), do: Map.put(map, key, value)

  defp prepare_for_save(:dataset, data) do
    data
    |> maybe_drop_empty("data")
    |> maybe_drop_empty("rows")
  end

  defp prepare_for_save(:scenario, data) do
    Map.update(data, "steps", [], fn steps ->
      Enum.map(steps, &prepare_step_for_save(&1, :scenario))
    end)
  end

  defp prepare_for_save(:suite, data) do
    Map.update(data, "testcases", [], fn testcases ->
      Enum.map(testcases, fn testcase ->
        Map.update(testcase, "steps", [], fn steps ->
          Enum.map(steps, &prepare_step_for_save(&1, :suite))
        end)
      end)
    end)
  end

  defp prepare_for_save(_kind, data), do: data

  defp prepare_step_for_save(%{"scenario" => scenario} = step, _context) do
    step
    |> Map.take(["name", "scenario", "dataset"])
    |> put_or_drop("scenario", scenario)
    |> strip_blank_optional_fields()
    |> clean_asserts()
  end

  defp prepare_step_for_save(step, :scenario) do
    step
    |> Map.take(["name", "client", "template", "assert", "save"])
    |> strip_blank_optional_fields()
    |> clean_asserts()
  end

  defp prepare_step_for_save(step, :suite) do
    step
    |> Map.take(["name", "client", "template", "dataset", "assert", "save"])
    |> strip_blank_optional_fields()
    |> clean_asserts()
  end

  defp strip_blank_optional_fields(step), do: put_or_drop(step, "name", step["name"])

  defp clean_asserts(%{"assert" => asserts} = step) do
    %{step | "assert" => Enum.map(asserts, &put_or_drop(&1, "path", &1["path"]))}
  end

  defp clean_asserts(step), do: step

  defp maybe_drop_empty(data, key) do
    case Map.get(data, key) do
      empty when empty in [%{}, [], nil] -> Map.delete(data, key)
      _present -> data
    end
  end

  defp steps_access_path("_"), do: [Access.key("steps", [])]

  defp steps_access_path(tc) do
    [Access.key("testcases", []), Access.at(String.to_integer(tc)), Access.key("steps", [])]
  end

  defp update_steps(socket, tc, fun) do
    update(socket, :data, &update_in(&1, steps_access_path(tc), fun))
  end

  defp update_steps_by_click(socket, %{"testcase_index" => tc}, fun) when tc not in [nil, ""] do
    update_steps(socket, tc, fun)
  end

  defp update_steps_by_click(socket, _params, fun) do
    update_steps(socket, "_", fun)
  end

  @doc """
  Writes `value` at `path` (a list of string map-keys/integer list-indices)
  within `data`, e.g. `["testcases", 0, "steps", 1, "dataset"]`. Used by
  `handle_info/2`'s `{:reference_picker, path, action}` clause, since a
  `MaestroWeb.Components.ReferencePicker` only knows the path to its own
  value, not which resource kind/shape it's embedded in.
  """
  def put_at_path(data, path, value) do
    put_in(data, access_path(path), value)
  end

  @doc "Reads the value at `path` within `data` (see `put_at_path/3`), or `nil`."
  def get_at_path(data, path) do
    get_in(data, access_path(path))
  end

  defp access_path(path) do
    Enum.map(path, fn
      segment when is_integer(segment) -> Access.at(segment)
      segment when is_binary(segment) -> Access.key(segment, [])
    end)
  end

  defp swap(list, i, j) when i < 0 or j < 0 or i >= length(list) or j >= length(list), do: list

  defp swap(list, i, j) do
    a = Enum.at(list, i)
    b = Enum.at(list, j)
    list |> List.replace_at(i, b) |> List.replace_at(j, a)
  end
end
