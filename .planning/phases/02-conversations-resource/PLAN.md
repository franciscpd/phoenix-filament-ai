# Phase 2: Conversations Resource — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admin users can browse, inspect, and manage all conversations through a paginated table with search/filters, a show page with message thread and metadata, inline edit, soft-delete, and JSON/Markdown export.

**Architecture:** Custom LiveView (`ConversationsLive`) with `PhoenixFilament.Table.InMemoryTableLive` for the index table (reuses PhoenixFilament's `TableRenderer` components). Show page reuses Phase 1's `MessageComponent` for the message thread. `StoreAdapter` extended with computed stats. `Exporter` module for JSON/Markdown export.

**Tech Stack:** Elixir, Phoenix LiveView, PhoenixFilament (TableRenderer, Column, Filter, Action, Params structs), PhoenixAI.Store (conversations, messages, cost records), Jason (JSON export)

**Spec:** `.planning/phases/02-conversations-resource/BRAINSTORM.md`
**Context:** `.planning/phases/02-conversations-resource/02-CONTEXT.md`

---

## File Structure

### Files to Create

| File | Responsibility |
|------|---------------|
| `lib/phoenix_filament/table/in_memory_table_live.ex` | Generic in-memory table LiveComponent |
| `lib/phoenix_filament_ai/conversations/conversations_live.ex` | LiveView (index + show) |
| `lib/phoenix_filament_ai/conversations/exporter.ex` | JSON + Markdown export |
| `test/phoenix_filament/table/in_memory_table_live_test.exs` | Table component unit tests |
| `test/phoenix_filament_ai/conversations/exporter_test.exs` | Export unit tests |
| `test/phoenix_filament_ai/conversations/conversations_live_test.exs` | LiveView tests |

### Files to Modify

| File | Change |
|------|--------|
| `lib/phoenix_filament_ai/store_adapter.ex` | Add `*_with_stats`, `sum_cost/2` |
| `lib/phoenix_filament/ai.ex` | Add conversations nav + route in `register/2` |
| `test/phoenix_filament_ai/store_adapter_test.exs` | Tests for new functions |

---

## Task 1: InMemoryTableLive — Core Pipeline

**Files:**
- Create: `lib/phoenix_filament/table/in_memory_table_live.ex`
- Create: `test/phoenix_filament/table/in_memory_table_live_test.exs`

This is the generic in-memory table component. Independent of conversations — tests use plain maps.

- [ ] **Step 1: Write failing tests for search and pagination**

```elixir
# test/phoenix_filament/table/in_memory_table_live_test.exs
defmodule PhoenixFilament.Table.InMemoryTableLiveTest do
  use ExUnit.Case, async: true

  alias PhoenixFilament.Table.InMemoryTableLive
  alias PhoenixFilament.Column

  @sample_rows [
    %{id: "1", name: "Alice", email: "alice@test.com", active: true, inserted_at: ~U[2026-01-15 10:00:00Z]},
    %{id: "2", name: "Bob", email: "bob@test.com", active: false, inserted_at: ~U[2026-02-20 12:00:00Z]},
    %{id: "3", name: "Charlie", email: "charlie@test.com", active: true, inserted_at: ~U[2026-03-10 08:00:00Z]},
    %{id: "4", name: "Diana", email: "diana@test.com", active: true, inserted_at: ~U[2026-04-05 14:00:00Z]}
  ]

  @columns [
    Column.new(:name, sortable: true, searchable: true),
    Column.new(:email, sortable: true, searchable: true),
    Column.new(:active),
    Column.new(:inserted_at, sortable: true)
  ]

  describe "apply_search/3" do
    test "filters rows by search term across searchable columns" do
      result = InMemoryTableLive.apply_search(@sample_rows, "alice", @columns)
      assert length(result) == 1
      assert hd(result).name == "Alice"
    end

    test "search is case-insensitive" do
      result = InMemoryTableLive.apply_search(@sample_rows, "BOB", @columns)
      assert length(result) == 1
      assert hd(result).name == "Bob"
    end

    test "search matches partial strings" do
      result = InMemoryTableLive.apply_search(@sample_rows, "li", @columns)
      # Matches "Alice" and "Charlie"
      assert length(result) == 2
    end

    test "empty search returns all rows" do
      result = InMemoryTableLive.apply_search(@sample_rows, "", @columns)
      assert length(result) == 4
    end

    test "nil search returns all rows" do
      result = InMemoryTableLive.apply_search(@sample_rows, nil, @columns)
      assert length(result) == 4
    end
  end

  describe "apply_sort/3" do
    test "sorts ascending by column" do
      result = InMemoryTableLive.apply_sort(@sample_rows, :name, :asc)
      assert Enum.map(result, & &1.name) == ["Alice", "Bob", "Charlie", "Diana"]
    end

    test "sorts descending by column" do
      result = InMemoryTableLive.apply_sort(@sample_rows, :name, :desc)
      assert Enum.map(result, & &1.name) == ["Diana", "Charlie", "Bob", "Alice"]
    end

    test "sorts by datetime column" do
      result = InMemoryTableLive.apply_sort(@sample_rows, :inserted_at, :desc)
      assert hd(result).name == "Diana"
    end
  end

  describe "apply_pagination/3" do
    test "returns correct page slice" do
      {rows, meta} = InMemoryTableLive.apply_pagination(@sample_rows, 1, 2)
      assert length(rows) == 2
      assert hd(rows).name == "Alice"
      assert meta.page == 1
      assert meta.per_page == 2
      assert meta.total == 4
    end

    test "returns second page" do
      {rows, _meta} = InMemoryTableLive.apply_pagination(@sample_rows, 2, 2)
      assert length(rows) == 2
      assert hd(rows).name == "Charlie"
    end

    test "handles last page with fewer items" do
      {rows, _meta} = InMemoryTableLive.apply_pagination(@sample_rows, 2, 3)
      assert length(rows) == 1
      assert hd(rows).name == "Diana"
    end

    test "returns empty list for out-of-range page" do
      {rows, meta} = InMemoryTableLive.apply_pagination(@sample_rows, 10, 2)
      assert rows == []
      assert meta.total == 4
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/phoenix_filament/table/in_memory_table_live_test.exs
```

Expected: FAIL — `InMemoryTableLive` module not defined.

- [ ] **Step 3: Implement the core pipeline functions**

```elixir
# lib/phoenix_filament/table/in_memory_table_live.ex
defmodule PhoenixFilament.Table.InMemoryTableLive do
  @moduledoc """
  Generic in-memory table LiveComponent.

  Drop-in replacement for `PhoenixFilament.Table.TableLive` that operates
  on in-memory lists instead of Ecto queries. Uses the same `Column`,
  `Filter`, `Action` structs and `TableRenderer` function components.

  ## Usage

      <.live_component
        module={PhoenixFilament.Table.InMemoryTableLive}
        id="my-table"
        rows={@data}
        columns={@columns}
        filters={@filters}
        actions={@actions}
        params={@params}
      />

  ## Parent Messages

  The parent LiveView must handle:

  - `{:table_patch, query_params}` — push_patch to update URL
  - `{:table_action, action_type, id}` — handle row action (view, delete, etc.)
  """

  use Phoenix.LiveComponent

  alias PhoenixFilament.Table.{Params, TableRenderer}
  import PhoenixFilament.Components.Modal, only: [modal: 1]

  # -------------------------------------------------------------------
  # Public pipeline functions (also used in tests)
  # -------------------------------------------------------------------

  @doc "Filters rows by search term across searchable columns."
  def apply_search(rows, search, _columns) when search in [nil, ""], do: rows

  def apply_search(rows, search, columns) do
    searchable_names =
      columns
      |> Enum.filter(fn col -> Keyword.get(col.opts, :searchable, false) end)
      |> Enum.map(& &1.name)

    downcased = String.downcase(search)

    Enum.filter(rows, fn row ->
      searchable_names
      |> Enum.map(fn name -> row |> Map.get(name) |> to_string() |> String.downcase() end)
      |> Enum.any?(&String.contains?(&1, downcased))
    end)
  end

  @doc "Sorts rows by column name and direction."
  def apply_sort(rows, sort_by, sort_dir) do
    sorted = Enum.sort_by(rows, &Map.get(&1, sort_by), fn a, b ->
      compare(a, b)
    end)

    if sort_dir == :desc, do: Enum.reverse(sorted), else: sorted
  end

  @doc "Returns a page slice and metadata."
  def apply_pagination(rows, page, per_page) do
    total = length(rows)
    offset = (page - 1) * per_page
    page_rows = Enum.slice(rows, offset, per_page)

    {page_rows, %{page: page, per_page: per_page, total: total}}
  end

  # DateTime/Date comparison for sort
  defp compare(%DateTime{} = a, %DateTime{} = b), do: DateTime.compare(a, b) != :gt
  defp compare(%Date{} = a, %Date{} = b), do: Date.compare(a, b) != :gt
  defp compare(a, b) when is_binary(a) and is_binary(b), do: a <= b
  defp compare(a, b) when is_number(a) and is_number(b), do: a <= b
  defp compare(nil, _), do: true
  defp compare(_, nil), do: false
  defp compare(a, b), do: to_string(a) <= to_string(b)
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
mix test test/phoenix_filament/table/in_memory_table_live_test.exs
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_filament/table/in_memory_table_live.ex test/phoenix_filament/table/in_memory_table_live_test.exs
git commit -m "feat(table): add InMemoryTableLive core pipeline (search, sort, paginate)"
```

---

## Task 2: InMemoryTableLive — Filters

**Files:**
- Modify: `lib/phoenix_filament/table/in_memory_table_live.ex`
- Modify: `test/phoenix_filament/table/in_memory_table_live_test.exs`

- [ ] **Step 1: Write failing tests for filters**

```elixir
# Add to in_memory_table_live_test.exs

  alias PhoenixFilament.Table.Filter

  @filters [
    %Filter{field: :active, type: :boolean, label: "Active"},
    %Filter{field: :inserted_at, type: :date_range, label: "Date"}
  ]

  describe "apply_filters/3" do
    test "boolean filter true" do
      active_filters = %{active: "true"}
      result = InMemoryTableLive.apply_filters(@sample_rows, active_filters, @filters)
      assert length(result) == 3
      assert Enum.all?(result, & &1.active)
    end

    test "boolean filter false" do
      active_filters = %{active: "false"}
      result = InMemoryTableLive.apply_filters(@sample_rows, active_filters, @filters)
      assert length(result) == 1
      refute hd(result).active
    end

    test "date_range filter" do
      active_filters = %{inserted_at: "2026-02-01|2026-03-31"}
      result = InMemoryTableLive.apply_filters(@sample_rows, active_filters, @filters)
      assert length(result) == 2
      names = Enum.map(result, & &1.name) |> Enum.sort()
      assert names == ["Bob", "Charlie"]
    end

    test "empty filters return all rows" do
      result = InMemoryTableLive.apply_filters(@sample_rows, %{}, @filters)
      assert length(result) == 4
    end

    test "select filter matches string value" do
      rows = [
        %{id: "1", status: "active"},
        %{id: "2", status: "deleted"},
        %{id: "3", status: "active"}
      ]

      filters = [%Filter{field: :status, type: :select, label: "Status"}]
      result = InMemoryTableLive.apply_filters(rows, %{status: "active"}, filters)
      assert length(result) == 2
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/phoenix_filament/table/in_memory_table_live_test.exs
```

Expected: FAIL — `apply_filters/3` not defined.

- [ ] **Step 3: Implement filter functions**

Add to `in_memory_table_live.ex`:

```elixir
  @doc "Applies active filters to rows based on filter definitions."
  def apply_filters(rows, active_filters, _filter_defs) when active_filters == %{}, do: rows

  def apply_filters(rows, active_filters, filter_defs) do
    Enum.reduce(filter_defs, rows, fn filter_def, acc ->
      case Map.get(active_filters, filter_def.field) do
        nil -> acc
        "" -> acc
        value -> apply_single_filter(acc, filter_def, value)
      end
    end)
  end

  defp apply_single_filter(rows, %Filter{type: :select, field: field}, value) do
    Enum.filter(rows, fn row -> to_string(Map.get(row, field)) == value end)
  end

  defp apply_single_filter(rows, %Filter{type: :boolean, field: field}, "true") do
    Enum.filter(rows, fn row -> Map.get(row, field) == true end)
  end

  defp apply_single_filter(rows, %Filter{type: :boolean, field: field}, "false") do
    Enum.filter(rows, fn row -> Map.get(row, field) == false end)
  end

  defp apply_single_filter(rows, %Filter{type: :date_range, field: field}, value) do
    case String.split(value, "|") do
      [from_str, to_str] ->
        with {:ok, from} <- Date.from_iso8601(from_str),
             {:ok, to} <- Date.from_iso8601(to_str) do
          Enum.filter(rows, fn row ->
            case Map.get(row, field) do
              %DateTime{} = dt ->
                date = DateTime.to_date(dt)
                Date.compare(date, from) != :lt and Date.compare(date, to) != :gt

              %Date{} = date ->
                Date.compare(date, from) != :lt and Date.compare(date, to) != :gt

              _ ->
                false
            end
          end)
        else
          _ -> rows
        end

      _ ->
        rows
    end
  end

  defp apply_single_filter(rows, _filter, _value), do: rows
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
mix test test/phoenix_filament/table/in_memory_table_live_test.exs
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_filament/table/in_memory_table_live.ex test/phoenix_filament/table/in_memory_table_live_test.exs
git commit -m "feat(table): add filter support to InMemoryTableLive (select, boolean, date_range)"
```

---

## Task 3: InMemoryTableLive — LiveComponent (update, events, render)

**Files:**
- Modify: `lib/phoenix_filament/table/in_memory_table_live.ex`

This task wires the pipeline functions into the LiveComponent lifecycle.

- [ ] **Step 1: Implement update/2 callback**

Add to `in_memory_table_live.ex`, above the pipeline functions:

```elixir
  alias PhoenixFilament.Table.Filter

  # -------------------------------------------------------------------
  # LiveComponent Lifecycle
  # -------------------------------------------------------------------

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    page_sizes = socket.assigns[:page_sizes] || [25, 50, 100]

    params =
      Params.parse(
        socket.assigns[:params] || %{},
        page_sizes: page_sizes
      )

    rows = socket.assigns.rows
    columns = socket.assigns.columns
    filters = socket.assigns[:filters] || []

    # Pipeline: search → filter → sort → paginate
    processed =
      rows
      |> apply_search(params.search, columns)
      |> apply_filters(params.filters, filters)
      |> apply_sort(params.sort_by, params.sort_dir)

    {page_rows, meta} = apply_pagination(processed, params.page, params.per_page)

    has_search = Enum.any?(columns, fn col -> Keyword.get(col.opts, :searchable, false) end)

    socket =
      socket
      |> assign(:parsed_params, params)
      |> assign(:meta, meta)
      |> assign(:has_search, has_search)
      |> assign_new(:confirm_delete, fn -> nil end)
      |> assign_new(:actions, fn -> [] end)
      |> assign_new(:filters, fn -> [] end)
      |> assign_new(:page_sizes, fn -> page_sizes end)
      |> assign_new(:empty_message, fn -> "No records found" end)
      |> assign_new(:empty_action, fn -> nil end)
      |> stream(:rows, page_rows, reset: true)

    {:ok, socket}
  end
```

- [ ] **Step 2: Implement event handlers**

Add to `in_memory_table_live.ex`:

```elixir
  # -------------------------------------------------------------------
  # Events (same interface as TableLive)
  # -------------------------------------------------------------------

  @impl true
  def handle_event("sort", %{"column" => column}, socket) do
    col = String.to_existing_atom(column)
    params = socket.assigns.parsed_params

    {sort_by, sort_dir} =
      if params.sort_by == col do
        {col, if(params.sort_dir == :asc, do: :desc, else: :asc)}
      else
        {col, :asc}
      end

    new_params = %{params | sort_by: sort_by, sort_dir: sort_dir, page: 1}
    push_table_patch(socket, new_params)
  end

  def handle_event("search", %{"search" => term}, socket) do
    new_params = %{socket.assigns.parsed_params | search: term, page: 1}
    push_table_patch(socket, new_params)
  end

  def handle_event("filter", params, socket) do
    filter_params = Map.get(params, "filter", %{})

    new_filters =
      Map.new(filter_params, fn {k, v} ->
        {String.to_existing_atom(k), v}
      end)

    new_params = %{socket.assigns.parsed_params | filters: new_filters, page: 1}
    push_table_patch(socket, new_params)
  rescue
    ArgumentError -> {:noreply, socket}
  end

  def handle_event("paginate", %{"page" => page}, socket) do
    new_params = %{socket.assigns.parsed_params | page: String.to_integer(page)}
    push_table_patch(socket, new_params)
  end

  def handle_event("per_page", %{"per_page" => per_page}, socket) do
    new_params = %{
      socket.assigns.parsed_params
      | per_page: String.to_integer(per_page),
        page: 1
    }

    push_table_patch(socket, new_params)
  end

  def handle_event("row_action", %{"action" => "delete", "id" => id}, socket) do
    {:noreply, assign(socket, :confirm_delete, id)}
  end

  def handle_event("row_action", %{"action" => action, "id" => id}, socket) do
    send(self(), {:table_action, String.to_existing_atom(action), id})
    {:noreply, socket}
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    send(self(), {:table_action, :delete, id})
    {:noreply, assign(socket, :confirm_delete, nil)}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, :confirm_delete, nil)}
  end

  defp push_table_patch(socket, params) do
    query_string = Params.to_query_string(params)
    send(self(), {:table_patch, query_string})
    {:noreply, socket}
  end
```

- [ ] **Step 3: Implement render/1**

Add to `in_memory_table_live.ex`:

```elixir
  # -------------------------------------------------------------------
  # Render
  # -------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <TableRenderer.search_bar
        :if={@has_search}
        search={@parsed_params.search}
        target={@myself}
      />

      <TableRenderer.filter_bar
        :if={@filters != []}
        filters={@filters}
        filter_values={@parsed_params.filters}
        target={@myself}
      />

      <div :if={@meta.total > 0} class="overflow-x-auto">
        <table class="table table-zebra">
          <TableRenderer.table_header
            columns={@columns}
            sort_by={@parsed_params.sort_by}
            sort_dir={@parsed_params.sort_dir}
            actions={@actions}
            target={@myself}
          />
          <tbody id={"#{@id}-rows"} phx-update="stream">
            <TableRenderer.table_row
              :for={{dom_id, row} <- @streams.rows}
              id={dom_id}
              columns={@columns}
              row={row}
              actions={@actions}
              target={@myself}
            />
          </tbody>
        </table>
      </div>

      <TableRenderer.empty_state
        :if={@meta.total == 0}
        message={@empty_message}
        action={@empty_action}
      />

      <TableRenderer.pagination
        :if={@meta.total > 0}
        page={@meta.page}
        per_page={@meta.per_page}
        total={@meta.total}
        page_sizes={@page_sizes}
        target={@myself}
      />

      <.modal
        :if={@confirm_delete}
        show={@confirm_delete != nil}
        id={"#{@id}-delete-modal"}
        on_cancel={nil}
      >
        <:header>Confirm Delete</:header>
        <p>Are you sure you want to delete this record? This action cannot be undone.</p>
        <:actions>
          <button
            class="btn btn-error"
            phx-click="confirm_delete"
            phx-value-id={@confirm_delete}
            phx-target={@myself}
          >
            Delete
          </button>
          <button class="btn btn-ghost" phx-click="cancel_delete" phx-target={@myself}>
            Cancel
          </button>
        </:actions>
      </.modal>
    </div>
    """
  end
```

Note: The `render/1` is nearly identical to `TableLive.render/1`. The only difference is the data source (in-memory pipeline in `update/2` instead of Ecto query). Verify `TableRenderer.empty_state/1` exists — if not, use a simple `<div>` with the empty message.

- [ ] **Step 4: Run full test suite to verify no regressions**

```bash
mix test
```

Expected: All existing tests pass. InMemoryTableLive tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_filament/table/in_memory_table_live.ex
git commit -m "feat(table): wire InMemoryTableLive LiveComponent (events, render, TableRenderer)"
```

---

## Task 4: StoreAdapter Extensions

**Files:**
- Modify: `lib/phoenix_filament_ai/store_adapter.ex`
- Modify: `test/phoenix_filament_ai/store_adapter_test.exs`

- [ ] **Step 1: Write failing tests for new functions**

Add to `store_adapter_test.exs`:

```elixir
  describe "get_conversation_with_stats/2" do
    test "returns conversation with message_count and total_cost" do
      {:ok, conv} =
        StoreAdapter.create_conversation(:test_store, %{title: "Stats Test"})

      {:ok, with_stats} = StoreAdapter.get_conversation_with_stats(:test_store, conv.id)

      assert with_stats.id == conv.id
      assert with_stats.title == "Stats Test"
      assert is_integer(with_stats.message_count)
      assert with_stats.message_count >= 0
      assert with_stats.total_cost != nil
    end

    test "returns error for non-existent conversation" do
      assert {:error, _} = StoreAdapter.get_conversation_with_stats(:test_store, "nonexistent")
    end
  end

  describe "list_conversations_with_stats/1" do
    test "returns list of conversations with stats" do
      {:ok, _} = StoreAdapter.create_conversation(:test_store, %{title: "Stats List 1"})
      {:ok, _} = StoreAdapter.create_conversation(:test_store, %{title: "Stats List 2"})

      result = StoreAdapter.list_conversations_with_stats(:test_store)

      assert is_list(result)
      assert length(result) >= 2

      first = hd(result)
      assert Map.has_key?(first, :message_count)
      assert Map.has_key?(first, :total_cost)
      assert Map.has_key?(first, :status)
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/phoenix_filament_ai/store_adapter_test.exs
```

Expected: FAIL — functions not defined.

- [ ] **Step 3: Implement new StoreAdapter functions**

Add to `lib/phoenix_filament_ai/store_adapter.ex`:

```elixir
  # --- Conversations with stats ---

  @doc "Loads a conversation with computed message_count and total_cost."
  @spec get_conversation_with_stats(atom(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def get_conversation_with_stats(store, id) do
    with {:ok, conv} <- get_conversation(store, id) do
      messages = conv.messages || []
      total_cost = compute_total_cost(store, id)
      status = if conv.deleted_at, do: :deleted, else: :active

      {:ok,
       conv
       |> Map.from_struct()
       |> Map.merge(%{
         message_count: length(messages),
         total_cost: total_cost,
         status: status
       })}
    end
  end

  @doc "Lists all conversations with computed stats for table display."
  @spec list_conversations_with_stats(atom(), keyword()) :: [map()]
  def list_conversations_with_stats(store, opts \\ []) do
    case list_conversations(store, opts) do
      {:ok, convs} ->
        Enum.map(convs, fn conv ->
          messages = conv.messages || []
          total_cost = compute_total_cost(store, conv.id)
          status = if conv.deleted_at, do: :deleted, else: :active

          conv
          |> Map.from_struct()
          |> Map.merge(%{
            message_count: length(messages),
            total_cost: total_cost,
            status: status
          })
        end)

      {:error, _} ->
        []
    end
  end

  defp compute_total_cost(store, conversation_id) do
    case PhoenixAI.Store.sum_cost([conversation_id: conversation_id], store: store) do
      {:ok, total} -> total
      {:error, _} -> Decimal.new("0")
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
mix test test/phoenix_filament_ai/store_adapter_test.exs
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_filament_ai/store_adapter.ex test/phoenix_filament_ai/store_adapter_test.exs
git commit -m "feat(store): add conversation stats functions (message_count, total_cost)"
```

---

## Task 5: Exporter Module

**Files:**
- Create: `lib/phoenix_filament_ai/conversations/exporter.ex`
- Create: `test/phoenix_filament_ai/conversations/exporter_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
# test/phoenix_filament_ai/conversations/exporter_test.exs
defmodule PhoenixFilamentAI.Conversations.ExporterTest do
  use ExUnit.Case, async: true

  alias PhoenixFilamentAI.Conversations.Exporter

  @conversation %{
    id: "conv-123",
    title: "Test Conversation",
    user_id: "user-1",
    tags: ["dev", "ops"],
    model: "gpt-4o",
    metadata: %{},
    inserted_at: ~U[2026-04-05 10:23:00Z],
    updated_at: ~U[2026-04-05 10:30:00Z],
    message_count: 2,
    total_cost: Decimal.new("0.34"),
    messages: [
      %{role: :user, content: "Hello", token_count: 5, inserted_at: ~U[2026-04-05 10:23:00Z], tool_calls: nil},
      %{role: :assistant, content: "Hi there! How can I help?", token_count: 12, inserted_at: ~U[2026-04-05 10:23:05Z], tool_calls: nil}
    ]
  }

  describe "to_json/1" do
    test "returns valid JSON" do
      json = Exporter.to_json(@conversation)
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["id"] == "conv-123"
      assert decoded["title"] == "Test Conversation"
    end

    test "includes all messages" do
      json = Exporter.to_json(@conversation)
      {:ok, decoded} = Jason.decode(json)
      assert length(decoded["messages"]) == 2
      assert hd(decoded["messages"])["role"] == "user"
    end

    test "includes metadata fields" do
      json = Exporter.to_json(@conversation)
      {:ok, decoded} = Jason.decode(json)
      assert decoded["user_id"] == "user-1"
      assert decoded["model"] == "gpt-4o"
      assert decoded["tags"] == ["dev", "ops"]
    end

    test "handles nil content in messages" do
      conv = put_in(@conversation, [:messages], [
        %{role: :user, content: nil, token_count: 0, inserted_at: ~U[2026-04-05 10:23:00Z], tool_calls: nil}
      ])

      json = Exporter.to_json(conv)
      assert {:ok, _} = Jason.decode(json)
    end

    test "handles empty messages" do
      conv = %{@conversation | messages: []}
      json = Exporter.to_json(conv)
      {:ok, decoded} = Jason.decode(json)
      assert decoded["messages"] == []
    end
  end

  describe "to_markdown/1" do
    test "includes title as heading" do
      md = Exporter.to_markdown(@conversation)
      assert md =~ "# Test Conversation"
    end

    test "includes metadata header" do
      md = Exporter.to_markdown(@conversation)
      assert md =~ "gpt-4o"
      assert md =~ "0.34"
    end

    test "formats messages with role labels" do
      md = Exporter.to_markdown(@conversation)
      assert md =~ "**User**"
      assert md =~ "**Assistant**"
      assert md =~ "Hello"
      assert md =~ "Hi there! How can I help?"
    end

    test "includes token count for assistant messages" do
      md = Exporter.to_markdown(@conversation)
      assert md =~ "12 tokens"
    end

    test "includes export footer" do
      md = Exporter.to_markdown(@conversation)
      assert md =~ "Exported from PhoenixFilamentAI"
    end

    test "handles nil content" do
      conv = put_in(@conversation, [:messages], [
        %{role: :user, content: nil, token_count: 0, inserted_at: ~U[2026-04-05 10:23:00Z], tool_calls: nil}
      ])

      md = Exporter.to_markdown(conv)
      assert is_binary(md)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/phoenix_filament_ai/conversations/exporter_test.exs
```

Expected: FAIL — module not defined.

- [ ] **Step 3: Implement Exporter module**

```elixir
# lib/phoenix_filament_ai/conversations/exporter.ex
defmodule PhoenixFilamentAI.Conversations.Exporter do
  @moduledoc """
  Exports conversations as JSON or Markdown documents.
  """

  @doc "Exports conversation as pretty-printed JSON binary."
  @spec to_json(map()) :: binary()
  def to_json(conversation) do
    %{
      id: conversation.id,
      title: conversation.title,
      user_id: conversation.user_id,
      tags: conversation.tags || [],
      model: conversation.model,
      metadata: conversation.metadata || %{},
      created_at: to_iso(conversation.inserted_at),
      updated_at: to_iso(conversation.updated_at),
      messages:
        Enum.map(conversation.messages || [], fn msg ->
          %{
            role: to_string(msg.role),
            content: msg.content,
            token_count: msg.token_count,
            timestamp: to_iso(msg.inserted_at),
            tool_calls: msg.tool_calls
          }
        end)
    }
    |> Jason.encode!(pretty: true)
  end

  @doc "Exports conversation as Markdown document."
  @spec to_markdown(map()) :: binary()
  def to_markdown(conversation) do
    title = conversation.title || "Untitled Conversation"
    model = conversation.model || "unknown"
    cost = format_cost(conversation[:total_cost])
    msg_count = length(conversation.messages || [])
    created = format_datetime(conversation.inserted_at)

    header = """
    # #{title}

    **Model:** #{model} | **Messages:** #{msg_count} | **Cost:** $#{cost}
    **Created:** #{created}

    ---
    """

    messages =
      (conversation.messages || [])
      |> Enum.map(&format_message/1)
      |> Enum.join("\n")

    footer = """

    ---
    *Exported from PhoenixFilamentAI on #{Date.utc_today() |> Date.to_iso8601()}*
    """

    header <> messages <> footer
  end

  defp format_message(msg) do
    role = msg.role |> to_string() |> String.capitalize()
    time = format_time(msg.inserted_at)
    content = msg.content || ""

    token_info =
      if msg.role == :assistant and msg.token_count do
        " — *#{msg.token_count} tokens*"
      else
        ""
      end

    """
    **#{role}** (#{time})#{token_info}:
    #{content}
    """
  end

  defp format_cost(nil), do: "0.00"
  defp format_cost(%Decimal{} = d), do: Decimal.to_string(d)
  defp format_cost(cost), do: to_string(cost)

  defp format_datetime(nil), do: "unknown"
  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")

  defp format_time(nil), do: "unknown"
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")

  defp to_iso(nil), do: nil
  defp to_iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
mix test test/phoenix_filament_ai/conversations/exporter_test.exs
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_filament_ai/conversations/exporter.ex test/phoenix_filament_ai/conversations/exporter_test.exs
git commit -m "feat(export): add conversation JSON and Markdown exporter"
```

---

## Task 6: ConversationsLive — Index View

**Files:**
- Create: `lib/phoenix_filament_ai/conversations/conversations_live.ex`
- Create: `test/phoenix_filament_ai/conversations/conversations_live_test.exs`

- [ ] **Step 1: Write failing tests for index view**

```elixir
# test/phoenix_filament_ai/conversations/conversations_live_test.exs
defmodule PhoenixFilamentAI.Conversations.ConversationsLiveTest do
  use ExUnit.Case, async: true

  alias PhoenixFilamentAI.ConversationsLive

  describe "ConversationsLive module" do
    test "module is defined and is a LiveView" do
      Code.ensure_loaded!(ConversationsLive)

      assert function_exported?(ConversationsLive, :mount, 3)
      assert function_exported?(ConversationsLive, :handle_params, 3)
      assert function_exported?(ConversationsLive, :handle_event, 3)
      assert function_exported?(ConversationsLive, :handle_info, 2)
      assert function_exported?(ConversationsLive, :render, 1)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
mix test test/phoenix_filament_ai/conversations/conversations_live_test.exs
```

Expected: FAIL — module not defined.

- [ ] **Step 3: Implement ConversationsLive with index view**

```elixir
# lib/phoenix_filament_ai/conversations/conversations_live.ex
defmodule PhoenixFilamentAI.ConversationsLive do
  @moduledoc """
  Full-screen LiveView for conversations management.

  Index view: paginated table with search, filters, sort, and actions.
  Show view: message thread with metadata sidebar, inline edit, export.

  Routes:
  - `/ai/conversations` — index (table)
  - `/ai/conversations/:id` — show (detail)
  """

  use Phoenix.LiveView

  alias PhoenixFilament.Column
  alias PhoenixFilament.Table.{Action, Filter, InMemoryTableLive}
  alias PhoenixFilamentAI.Conversations.Exporter
  alias PhoenixFilamentAI.Components.{MessageComponent, Markdown}
  alias PhoenixFilamentAI.StoreAdapter

  require Logger

  # -------------------------------------------------------------------
  # Column / Filter / Action definitions
  # -------------------------------------------------------------------

  defp columns do
    [
      Column.new(:title, sortable: true, searchable: true),
      Column.new(:user_id, label: "User", sortable: true, searchable: true),
      Column.new(:message_count, label: "Messages", sortable: true,
        format: fn val, _row -> to_string(val || 0) end),
      Column.new(:total_cost, label: "Cost", sortable: true,
        format: fn val, _row -> "$#{format_cost(val)}" end),
      Column.new(:tags, label: "Tags",
        format: fn val, _row -> (val || []) |> Enum.join(", ") end),
      Column.new(:status, label: "Status",
        format: fn val, _row -> to_string(val || :active) end,
        badge: true),
      Column.new(:inserted_at, label: "Created", sortable: true,
        format: fn val, _row -> format_date(val) end)
    ]
  end

  defp filters do
    [
      %Filter{field: :status, label: "Status", type: :select,
              options: [{"Active", "active"}, {"Deleted", "deleted"}]},
      %Filter{field: :inserted_at, label: "Date", type: :date_range}
    ]
  end

  defp actions do
    [
      %Action{type: :view, label: "View", icon: "hero-eye"},
      %Action{type: :delete, label: "Delete", icon: "hero-trash", confirm: true}
    ]
  end

  # -------------------------------------------------------------------
  # Lifecycle
  # -------------------------------------------------------------------

  @impl true
  def mount(_params, _session, socket) do
    config = socket.assigns[:ai_config] || default_config()
    store = config[:store]

    conversations = StoreAdapter.list_conversations_with_stats(store)

    {:ok,
     socket
     |> assign(:store, store)
     |> assign(:config, config)
     |> assign(:conversations, conversations)
     |> assign(:view, :index)
     |> assign(:conversation, nil)
     |> assign(:editing, nil)
     |> assign(:page_title, "Conversations")}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case StoreAdapter.get_conversation_with_stats(socket.assigns.store, id) do
      {:ok, conversation} ->
        {:noreply,
         socket
         |> assign(:view, :show)
         |> assign(:conversation, conversation)
         |> assign(:page_title, conversation.title || "Conversation")}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Conversation not found")
         |> push_patch(to: "/ai/conversations")}
    end
  end

  def handle_params(_params, _uri, socket) do
    conversations = StoreAdapter.list_conversations_with_stats(socket.assigns.store)

    {:noreply,
     socket
     |> assign(:view, :index)
     |> assign(:conversations, conversations)
     |> assign(:conversation, nil)
     |> assign(:page_title, "Conversations")}
  end

  # -------------------------------------------------------------------
  # Events — Index
  # -------------------------------------------------------------------

  @impl true
  def handle_event("export_json", _params, socket) do
    conv = socket.assigns.conversation
    json = Exporter.to_json(conv)
    {:noreply, push_event(socket, "download", %{data: json, filename: "conversation-#{conv.id}.json", content_type: "application/json"})}
  end

  def handle_event("export_markdown", _params, socket) do
    conv = socket.assigns.conversation
    md = Exporter.to_markdown(conv)
    {:noreply, push_event(socket, "download", %{data: md, filename: "conversation-#{conv.id}.md", content_type: "text/markdown"})}
  end

  def handle_event("edit_start", %{"field" => field}, socket) do
    {:noreply, assign(socket, :editing, String.to_existing_atom(field))}
  end

  def handle_event("edit_cancel", _params, socket) do
    {:noreply, assign(socket, :editing, nil)}
  end

  def handle_event("edit_save", %{"field" => "title", "value" => value}, socket) do
    save_field(socket, :title, value)
  end

  def handle_event("edit_save", %{"field" => "tags", "value" => value}, socket) do
    tags = value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    save_field(socket, :tags, tags)
  end

  def handle_event("delete_conversation", _params, socket) do
    case socket.assigns.conversation do
      nil ->
        {:noreply, socket}

      conv ->
        StoreAdapter.delete_conversation(socket.assigns.store, conv.id)

        {:noreply,
         socket
         |> put_flash(:info, "Conversation deleted")
         |> push_patch(to: "/ai/conversations")}
    end
  end

  # -------------------------------------------------------------------
  # Info — Table messages
  # -------------------------------------------------------------------

  @impl true
  def handle_info({:table_patch, params}, socket) do
    {:noreply, push_patch(socket, to: "/ai/conversations?#{params}")}
  end

  def handle_info({:table_action, :view, id}, socket) do
    {:noreply, push_patch(socket, to: "/ai/conversations/#{id}")}
  end

  def handle_info({:table_action, :delete, id}, socket) do
    StoreAdapter.delete_conversation(socket.assigns.store, id)
    conversations = StoreAdapter.list_conversations_with_stats(socket.assigns.store)

    {:noreply,
     socket
     |> assign(:conversations, conversations)
     |> put_flash(:info, "Conversation deleted")}
  end

  # -------------------------------------------------------------------
  # Render
  # -------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pfa-conversations-page">
      <%= if @view == :index do %>
        <.index_view
          conversations={@conversations}
          columns={columns()}
          filters={filters()}
          actions={actions()}
          params={%{}}
        />
      <% else %>
        <.show_view
          conversation={@conversation}
          editing={@editing}
        />
      <% end %>
    </div>
    """
  end

  defp index_view(assigns) do
    ~H"""
    <div class="pfa-conversations-index">
      <div class="pfa-conversations-header">
        <h1 class="pfa-conversations-title">Conversations</h1>
      </div>

      <.live_component
        module={InMemoryTableLive}
        id="conversations-table"
        rows={@conversations}
        columns={@columns}
        filters={@filters}
        actions={@actions}
        params={@params}
        empty_message="No conversations yet. Start chatting to see conversations here."
      />
    </div>
    """
  end

  defp show_view(assigns) do
    ~H"""
    <div class="pfa-conversations-show">
      <div class="pfa-conversations-back">
        <.link patch="/ai/conversations" class="pfa-back-link">
          ← Back to conversations
        </.link>
      </div>

      <div class="pfa-conversations-show-layout">
        <div class="pfa-conversations-thread">
          <div class="pfa-conversations-messages">
            <div :for={msg <- @conversation.messages || []} class="pfa-message-wrapper">
              <div class="pfa-message-timestamp">
                {format_time(msg.inserted_at)}
              </div>
              <MessageComponent.message
                message={msg}
                streaming={false}
                on_retry={nil}
              />
              <div :if={msg.role == :assistant and msg.token_count} class="pfa-message-tokens">
                {msg.token_count} tokens
              </div>
            </div>
          </div>

          <div class="pfa-conversations-footer">
            Total: ${format_cost(@conversation.total_cost)}
            — {format_number(total_tokens(@conversation))} tokens
            ({@conversation.message_count} messages)
          </div>
        </div>

        <div class="pfa-conversations-sidebar">
          <div class="pfa-sidebar-section">
            <div class="pfa-sidebar-label">Title</div>
            <%= if @editing == :title do %>
              <form phx-submit="edit_save">
                <input type="hidden" name="field" value="title" />
                <input
                  type="text"
                  name="value"
                  value={@conversation.title}
                  class="pfa-edit-input"
                  phx-keydown="edit_cancel"
                  phx-key="Escape"
                  autofocus
                />
              </form>
            <% else %>
              <div class="pfa-sidebar-value pfa-editable" phx-click="edit_start" phx-value-field="title">
                {@conversation.title || "Untitled"}
              </div>
            <% end %>
          </div>

          <div class="pfa-sidebar-section">
            <div class="pfa-sidebar-label">Tags</div>
            <%= if @editing == :tags do %>
              <form phx-submit="edit_save">
                <input type="hidden" name="field" value="tags" />
                <input
                  type="text"
                  name="value"
                  value={(@conversation.tags || []) |> Enum.join(", ")}
                  class="pfa-edit-input"
                  phx-keydown="edit_cancel"
                  phx-key="Escape"
                  autofocus
                />
              </form>
            <% else %>
              <div class="pfa-sidebar-value pfa-editable" phx-click="edit_start" phx-value-field="tags">
                <span :for={tag <- @conversation.tags || []} class="pfa-tag-badge">{tag}</span>
                <span :if={(@conversation.tags || []) == []} class="pfa-empty-text">No tags</span>
              </div>
            <% end %>
          </div>

          <div class="pfa-sidebar-section">
            <div class="pfa-sidebar-label">Model</div>
            <div class="pfa-sidebar-value">{@conversation.model || "—"}</div>
          </div>

          <div class="pfa-sidebar-section">
            <div class="pfa-sidebar-label">Messages</div>
            <div class="pfa-sidebar-value">{@conversation.message_count}</div>
          </div>

          <div class="pfa-sidebar-section">
            <div class="pfa-sidebar-label">Total Cost</div>
            <div class="pfa-sidebar-value">${format_cost(@conversation.total_cost)}</div>
          </div>

          <div class="pfa-sidebar-section">
            <div class="pfa-sidebar-label">Created</div>
            <div class="pfa-sidebar-value">{format_datetime(@conversation.inserted_at)}</div>
          </div>

          <div class="pfa-sidebar-section">
            <div class="pfa-sidebar-label">Updated</div>
            <div class="pfa-sidebar-value">{format_datetime(@conversation.updated_at)}</div>
          </div>

          <div class="pfa-sidebar-actions">
            <button phx-click="export_json" class="pfa-export-btn">Export JSON</button>
            <button phx-click="export_markdown" class="pfa-export-btn">Export Markdown</button>
          </div>

          <div class="pfa-sidebar-danger">
            <button
              phx-click="delete_conversation"
              class="pfa-delete-btn"
              data-confirm="Are you sure? This will soft-delete the conversation."
            >
              Delete conversation
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp save_field(socket, field, value) do
    conv = socket.assigns.conversation
    store = socket.assigns.store

    case StoreAdapter.update_conversation(store, conv.id, %{field => value}) do
      {:ok, _updated} ->
        {:ok, refreshed} = StoreAdapter.get_conversation_with_stats(store, conv.id)

        {:noreply,
         socket
         |> assign(:conversation, refreshed)
         |> assign(:editing, nil)}

      {:error, reason} ->
        Logger.error("Failed to update conversation: #{inspect(reason)}")
        {:noreply, socket |> put_flash(:error, "Failed to save") |> assign(:editing, nil)}
    end
  end

  defp format_cost(nil), do: "0.00"
  defp format_cost(%Decimal{} = d), do: Decimal.to_string(d)
  defp format_cost(cost), do: to_string(cost)

  defp format_date(nil), do: "—"
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")

  defp format_datetime(nil), do: "—"
  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y %H:%M")

  defp format_time(nil), do: ""
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")

  defp format_number(n) when is_integer(n), do: Number.Delimit.number_to_delimited(n, precision: 0)
  defp format_number(n), do: to_string(n)

  defp total_tokens(conversation) do
    (conversation.messages || [])
    |> Enum.map(& &1.token_count)
    |> Enum.reject(&is_nil/1)
    |> Enum.sum()
  end

  defp default_config do
    [store: nil, provider: nil, model: nil, chat: []]
  end
end
```

Note: The `format_number/1` helper uses a delimiter function. If `Number` library is not available, use a simple `to_string(n)` fallback or implement inline: `Integer.to_string(n) |> String.reverse() |> String.replace(~r/(\d{3})/, "\\1,") |> String.reverse() |> String.trim_leading(",")`. Verify during implementation.

Note: The export uses `push_event(socket, "download", ...)` which requires a client-side JS hook to trigger the actual download. Alternative: use Phoenix's built-in `send_download/3` if available in the current LiveView version. Verify during implementation and adjust accordingly.

- [ ] **Step 4: Run tests to verify they pass**

```bash
mix test test/phoenix_filament_ai/conversations/conversations_live_test.exs
```

Expected: PASS

- [ ] **Step 5: Run full test suite**

```bash
mix test
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_filament_ai/conversations/conversations_live.ex test/phoenix_filament_ai/conversations/conversations_live_test.exs
git commit -m "feat(conversations): add ConversationsLive with index table and show page"
```

---

## Task 7: Plugin Integration

**Files:**
- Modify: `lib/phoenix_filament/ai.ex`
- Modify: `test/phoenix_filament_ai/plugin_test.exs`

- [ ] **Step 1: Write failing test**

Add to `plugin_test.exs`:

```elixir
  test "includes conversations navigation when conversations is enabled" do
    opts = PhoenixFilamentAI.Fixtures.valid_plugin_opts(conversations: true)
    result = AI.register(%{}, opts)

    conv_nav = Enum.find(result.nav_items, fn item -> item.label == "Conversations" end)
    assert conv_nav != nil
    assert conv_nav.path == "/ai/conversations"
  end

  test "excludes conversations navigation when conversations is disabled" do
    opts = PhoenixFilamentAI.Fixtures.valid_plugin_opts(conversations: false)
    result = AI.register(%{}, opts)

    conv_nav = Enum.find(result.nav_items, fn item -> item.label == "Conversations" end)
    assert conv_nav == nil
  end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
mix test test/phoenix_filament_ai/plugin_test.exs
```

Expected: FAIL — conversations nav not added yet.

- [ ] **Step 3: Update register/2 in ai.ex**

Modify `build_nav_items/1` in `lib/phoenix_filament/ai.ex` to add conversations:

```elixir
  defp build_nav_items(config) do
    nav_group = Keyword.get(config, :nav_group, "AI")
    items = []

    items =
      if Keyword.get(config, :chat_page, true) do
        items ++ [%{label: "Chat", icon: "hero-chat-bubble-left-right", group: nav_group, path: "/ai/chat"}]
      else
        items
      end

    items =
      if Keyword.get(config, :conversations, false) do
        items ++ [%{label: "Conversations", icon: "hero-chat-bubble-left-ellipsis", group: nav_group, path: "/ai/conversations"}]
      else
        items
      end

    items
  end
```

Similarly update `build_routes/1`:

```elixir
  defp build_routes(config) do
    routes = []

    routes =
      if Keyword.get(config, :chat_page, true) do
        routes ++ [%{path: "/ai/chat", live: PhoenixFilamentAI.ChatLive}]
      else
        routes
      end

    routes =
      if Keyword.get(config, :conversations, false) do
        routes ++ [%{path: "/ai/conversations", live: PhoenixFilamentAI.ConversationsLive}]
      else
        routes
      end

    routes
  end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
mix test test/phoenix_filament_ai/plugin_test.exs
```

Expected: PASS

- [ ] **Step 5: Run full test suite**

```bash
mix test && mix format --check-formatted && mix credo --strict
```

Expected: All pass, no format/credo issues.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_filament/ai.ex test/phoenix_filament_ai/plugin_test.exs
git commit -m "feat(plugin): register conversations nav and route when enabled"
```

---

## Requirement Coverage

| Requirement | Task | How |
|-------------|------|-----|
| CONV-01 | Task 6 | ConversationsLive index with InMemoryTableLive — paginated table |
| CONV-02 | Task 6 | Columns: title, user, message_count, total_cost, tags (badges), status (badge), created_at — sortable via InMemoryTableLive |
| CONV-03 | Task 1-3, 6 | InMemoryTableLive search (title, user) + filters (status select, date_range) |
| CONV-04 | Task 6 | Show page: MessageComponent renders thread, user right, assistant left |
| CONV-05 | Task 4, 6 | Per-message token_count inline, accumulated cost in footer |
| CONV-06 | Task 6 | Inline edit title and tags via edit_start/edit_save events |
| CONV-07 | Task 6 | Soft-delete via StoreAdapter.delete_conversation, delete action on table |
| CONV-08 | Task 5, 6 | Exporter.to_json + to_markdown, export buttons on show page |
