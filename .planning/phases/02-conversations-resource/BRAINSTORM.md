# Phase 2: Conversations Resource — Design Spec

**Date:** 2026-04-06
**Status:** Approved
**Approach:** Custom LiveView with InMemoryTableLive (reuses PhoenixFilament TableRenderer) + chat-style show page reusing Phase 1 components

---

## 1. Architecture Overview

```
ConversationsLive (LiveView)
  ├─ handle_params → route between index and show views
  ├─ handle_info({:table_patch, ...}) → push_patch with new URL params
  ├─ handle_info({:table_action, ...}) → delete, view, export
  │
  ├─ Index view (/ai/conversations)
  │   └─ PhoenixFilament.Table.InMemoryTableLive (LiveComponent)
  │       ├─ Accepts: rows (list), columns, filters, actions, params
  │       ├─ In-memory: search, filter, sort, paginate via Enum
  │       └─ Renders: TableRenderer.* (from PhoenixFilament)
  │
  └─ Show view (/ai/conversations/:id)
      ├─ Conversation header (title + tags, inline edit)
      ├─ Message thread (reuses MessageComponent from Phase 1)
      ├─ Metadata sidebar (cost, tokens, timestamps, model)
      ├─ Per-message token display + accumulated cost footer
      └─ Export buttons (JSON, Markdown) + Delete button
```

Single LiveView with `handle_params/3` for routing between index and show. `push_patch` for SPA-like navigation without full reload. Conversations feature gated behind `conversations: true` in plugin config.

---

## 2. InMemoryTableLive — Generic Table Component

### Module: `PhoenixFilament.Table.InMemoryTableLive`

Drop-in replacement for `PhoenixFilament.Table.TableLive` that operates on in-memory lists instead of Ecto queries. Uses the same `Column`, `Filter`, `Action` structs and the same `TableRenderer` function components. Designed for future migration into the phoenix_filament core library.

### Public Interface

```elixir
<.live_component
  module={PhoenixFilament.Table.InMemoryTableLive}
  id="conversations-table"
  rows={@conversations}
  columns={@columns}
  filters={@filters}
  actions={@actions}
  params={@params}
  row_id={fn row -> row.id end}
  empty_message="No conversations yet"
/>
```

### Assigns

| Assign | Type | Required | Description |
|--------|------|----------|-------------|
| `rows` | list | yes | Full dataset — component handles filter/sort/paginate |
| `columns` | `[%Column{}]` | yes | Column definitions (same struct as PhoenixFilament) |
| `filters` | `[%Filter{}]` | no | Filter definitions (`:select`, `:boolean`, `:date_range`) |
| `actions` | `[%Action{}]` | no | Row actions (view, delete, custom) |
| `params` | map | no | Raw URL params for initial state |
| `row_id` | function | no | `fn row -> unique_id` (default: `& &1.id`) |
| `page_sizes` | list | no | Allowed page sizes (default: `[25, 50, 100]`) |
| `empty_message` | string | no | Empty state text |
| `empty_action` | map | no | CTA for empty state (`%{label:, event:}`) |

### Internal Pipeline

```
rows (full list)
  │
  ├─ 1. Search: Enum.filter — text match (case-insensitive) on searchable columns
  ├─ 2. Filter: Enum.filter — apply active filters by type (:select, :boolean, :date_range)
  ├─ 3. Sort: Enum.sort_by — sort_by column, sort_dir :asc/:desc
  ├─ 4. Count: length(filtered) → total
  ├─ 5. Paginate: Enum.slice(offset, per_page)
  └─ 6. Stream: stream(:rows, paginated, reset: true)
```

### Events (same as TableLive)

| Event | Params | Behavior |
|-------|--------|----------|
| `sort` | `%{"column" => col}` | Toggle sort direction, reset to page 1 |
| `search` | `%{"search" => term}` | Text search on searchable columns, reset to page 1 |
| `filter` | `%{"filter" => %{field => value}}` | Apply filters, reset to page 1 |
| `paginate` | `%{"page" => page}` | Navigate to page |
| `per_page` | `%{"per_page" => size}` | Change page size, reset to page 1 |
| `row_action` | `%{"action" => type, "id" => id}` | Forward to parent via `{:table_action, type, id}` |

### Parent Messages

- `{:table_patch, query_string}` — parent must `push_patch` to update URL
- `{:table_action, action_type, id}` — parent handles CRUD action

### Render

Delegates entirely to `TableRenderer.*` function components:
- `TableRenderer.search_bar/1`
- `TableRenderer.filter_bar/1`
- `TableRenderer.table_header/1`
- `TableRenderer.table_row/1`
- `TableRenderer.pagination/1`
- `TableRenderer.empty_state/1` (if available) or custom empty state

### Filter Implementation

| Filter type | Matching logic |
|-------------|----------------|
| `:select` | `Map.get(row, field) == value` (string equality) |
| `:boolean` | `Map.get(row, field) == true` / `== false` |
| `:date_range` | `date >= from and date <= to` on DateTime fields |

### Search Implementation

For each row, concatenate values of searchable columns into a single string, downcase, check if it contains the downcased search term. Same logic as `chat_page.ex` sidebar search but generalized.

---

## 3. ConversationsLive — Index View

### Module: `PhoenixFilamentAI.ConversationsLive`

Single LiveView handling both index (`/ai/conversations`) and show (`/ai/conversations/:id`) via `handle_params/3`.

### Mount & Data Loading

```elixir
def mount(_params, _session, socket) do
  store = socket.assigns.ai_store
  config = socket.assigns.ai_config
  conversations = StoreAdapter.list_conversations_with_stats(store)

  {:ok,
   socket
   |> assign(:store, store)
   |> assign(:config, config)
   |> assign(:conversations, conversations)
   |> assign(:view, :index)           # :index or :show
   |> assign(:conversation, nil)      # loaded on show
   |> assign(:editing, nil)}          # :title or :tags when inline editing
end
```

### handle_params Routing

```elixir
def handle_params(%{"id" => id}, _uri, socket) do
  # Show view
  case StoreAdapter.get_conversation_with_stats(socket.assigns.store, id) do
    {:ok, conversation} ->
      {:noreply, assign(socket, view: :show, conversation: conversation)}
    {:error, _} ->
      {:noreply, socket |> put_flash(:error, "Conversation not found") |> push_patch(to: "/ai/conversations")}
  end
end

def handle_params(_params, _uri, socket) do
  # Index view — refresh conversations list
  conversations = StoreAdapter.list_conversations_with_stats(socket.assigns.store)
  {:noreply, assign(socket, view: :index, conversations: conversations, conversation: nil)}
end
```

### Table Columns

```elixir
@columns [
  %Column{name: :title, label: "Title", opts: [sortable: true, searchable: true]},
  %Column{name: :user_id, label: "User", opts: [sortable: true, searchable: true]},
  %Column{name: :message_count, label: "Messages", opts: [sortable: true],
          render: fn row -> row.message_count end},
  %Column{name: :total_cost, label: "Cost", opts: [sortable: true],
          render: fn row -> format_cost(row.total_cost) end},
  %Column{name: :tags, label: "Tags",
          render: fn row -> render_tag_badges(row.tags) end},
  %Column{name: :status, label: "Status",
          render: fn row -> render_status_badge(row) end},
  %Column{name: :inserted_at, label: "Created", opts: [sortable: true],
          render: fn row -> format_date(row.inserted_at) end}
]
```

### Table Filters

```elixir
@filters [
  %Filter{field: :status, label: "Status", type: :select,
          options: [{"Active", "active"}, {"Deleted", "deleted"}, {"All", "all"}]},
  %Filter{field: :tags, label: "Tags", type: :select,
          options: fn rows -> extract_unique_tags(rows) end},
  %Filter{field: :inserted_at, label: "Date", type: :date_range}
]
```

Note: Tag filter options are populated dynamically from the loaded conversations.

### Table Actions

```elixir
@actions [
  %Action{type: :view, label: "View", icon: "hero-eye"},
  %Action{type: :delete, label: "Delete", icon: "hero-trash", confirm: true}
]
```

### Event Handlers

```elixir
# Table routing
def handle_info({:table_patch, params}, socket) do
  {:noreply, push_patch(socket, to: "/ai/conversations?#{params}")}
end

def handle_info({:table_action, :view, id}, socket) do
  {:noreply, push_patch(socket, to: "/ai/conversations/#{id}")}
end

def handle_info({:table_action, :delete, id}, socket) do
  StoreAdapter.delete_conversation(socket.assigns.store, id)
  conversations = StoreAdapter.list_conversations_with_stats(socket.assigns.store)
  {:noreply, socket |> assign(:conversations, conversations) |> put_flash(:info, "Conversation deleted")}
end
```

### Empty State

"No conversations yet. Start chatting to see conversations here." with optional link to chat page.

---

## 4. ConversationsLive — Show View

### Layout

2-column layout: message thread (~75%) + metadata sidebar (~25%).

### Message Thread

- Read-only — no input area, no send button
- Reuses `MessageComponent.message/1` from Phase 1
- User messages right-aligned, assistant messages left-aligned
- Each message shows timestamp (small text above)
- Each assistant message shows token count (small text below: "123 in → 456 out")
- Markdown rendering via `Markdown.render_complete/1`
- Tool calls render as collapsible `ToolCallCard`
- Scroll container with all messages loaded (no lazy loading for show view)

### Metadata Sidebar

| Field | Display | Editable |
|-------|---------|----------|
| Title | Text, click to edit inline | ✓ |
| Tags | Pill badges, click to edit | ✓ |
| Model | Text (e.g., "gpt-4o") | ✗ |
| Messages | Count | ✗ |
| Total cost | Formatted decimal (e.g., "$0.34") | ✗ |
| Total tokens | Formatted number (e.g., "4,210") | ✗ |
| Created | Date with time | ✗ |
| Updated | Date with time | ✗ |

### Inline Edit

- **Title:** Click title → shows text input with current value. Enter or blur to save. Esc to cancel. Calls `StoreAdapter.update_conversation/3`.
- **Tags:** Click tags area → shows comma-separated text input. Enter or blur to save. Parses into list, trims whitespace. Calls `StoreAdapter.update_conversation/3`.

### Footer

Accumulated cost summary bar at bottom of thread: "Total: $0.34 — 4,210 tokens (12 messages)"

### Export Buttons

- "Export JSON" → `send_download(socket, Exporter.to_json(conversation), filename: "conversation-#{id}.json")`
- "Export Markdown" → `send_download(socket, Exporter.to_markdown(conversation), filename: "conversation-#{id}.md")`

### Delete

Red "Delete conversation" button in sidebar footer. Soft-delete with confirmation modal. On confirm, redirects to index via `push_patch`.

### Back Navigation

"← Back to conversations" link at top, uses `push_patch(to: "/ai/conversations")`.

---

## 5. Export Module

### Module: `PhoenixFilamentAI.Conversations.Exporter`

```elixir
defmodule PhoenixFilamentAI.Conversations.Exporter do
  @doc "Exports conversation as pretty-printed JSON binary."
  @spec to_json(conversation :: map()) :: binary()
  def to_json(conversation)
  # Includes: id, title, user_id, tags, model, metadata, timestamps,
  # messages: [{role, content, token_count, inserted_at, tool_calls}]
  # Uses Jason.encode!(data, pretty: true)

  @doc "Exports conversation as Markdown document."
  @spec to_markdown(conversation :: map()) :: binary()
  def to_markdown(conversation)
  # Format:
  # # {title}
  #
  # **Model:** gpt-4o | **Messages:** 12 | **Cost:** $0.34
  # **Created:** 2026-04-05 10:23 UTC
  #
  # ---
  #
  # **User** (10:23 AM):
  # {content — raw markdown, not rendered to HTML}
  #
  # **Assistant** (10:23 AM) — *123 tokens*:
  # {content}
  #
  # ---
  # *Exported from PhoenixFilamentAI on {date}*
end
```

Messages in Markdown export use raw content (not HTML-rendered). This means code blocks, bold, lists etc. are preserved as-is — the exported .md file is itself valid Markdown.

---

## 6. StoreAdapter Extensions

### New Functions

```elixir
defmodule PhoenixFilamentAI.StoreAdapter do
  # ... existing functions from Phase 1 ...

  @doc "Loads a conversation with computed message_count and total_cost."
  @spec get_conversation_with_stats(atom(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def get_conversation_with_stats(store, id)
  # 1. load_conversation (includes messages)
  # 2. message_count = length(messages)
  # 3. total_cost = sum of cost records (or computed from message token_counts)
  # Returns conversation map with :message_count and :total_cost keys added

  @doc "Lists all conversations with computed stats for table display."
  @spec list_conversations_with_stats(atom(), keyword()) ::
          [map()]
  def list_conversations_with_stats(store, opts \\ [])
  # 1. list_conversations (returns conversations without messages)
  # 2. For each: compute message_count and total_cost
  # Note: This may need to load each conversation to count messages,
  # or use Store.get_messages/2 count if available.
  # Returns list of maps with :message_count, :total_cost, :status added

  @doc "Sums cost for given filters. Delegates to Store.sum_cost/2."
  @spec sum_cost(atom(), keyword()) ::
          {:ok, Decimal.t()} | {:error, term()}
  def sum_cost(store, filters \\ [])
end
```

### Computed Fields

- `message_count` — `length(conversation.messages)` or count from `Store.get_messages/2`
- `total_cost` — from `Store.sum_cost/2` with `conversation_id: id` filter, or `Decimal.new(0)` if cost tracking not configured
- `status` — `:active` if `deleted_at` is nil, `:deleted` otherwise

---

## 7. Plugin Integration

### register/2 Changes

When `conversations: true` in config:

```elixir
# Nav item
%{label: "Conversations", icon: "hero-chat-bubble-left-ellipsis",
  group: nav_group, path: "/ai/conversations"}

# Route
%{path: "/ai/conversations", live: PhoenixFilamentAI.ConversationsLive}
```

Note: The route pattern must also match `/ai/conversations/:id` for the show view. This may require a wildcard or two separate route entries depending on PhoenixFilament's routing mechanism.

### Config

`conversations` option already defined in NimbleOptions schema (default: `false`). No changes needed to config — just flip to `true` when Phase 2 ships.

---

## 8. File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `lib/phoenix_filament/table/in_memory_table_live.ex` | Generic in-memory table LiveComponent |
| `lib/phoenix_filament_ai/conversations/conversations_live.ex` | LiveView (index + show) |
| `lib/phoenix_filament_ai/conversations/exporter.ex` | JSON + Markdown export |
| `test/phoenix_filament/table/in_memory_table_live_test.exs` | Table component unit tests |
| `test/phoenix_filament_ai/conversations/conversations_live_test.exs` | LiveView tests |
| `test/phoenix_filament_ai/conversations/exporter_test.exs` | Export unit tests |

### Modified Files

| File | Change |
|------|--------|
| `lib/phoenix_filament/ai.ex` | Add conversations nav + route in `register/2` |
| `lib/phoenix_filament_ai/store_adapter.ex` | Add `*_with_stats` functions, `sum_cost/2` |
| `test/phoenix_filament_ai/store_adapter_test.exs` | Tests for new functions |

---

## 9. Testing Strategy

### Unit Tests

- **InMemoryTableLive** — search (case-insensitive, multi-column), each filter type (:select, :boolean, :date_range), sort (asc/desc, by different types), pagination (page navigation, per_page change, edge cases), empty state
- **Exporter.to_json** — valid JSON structure, all fields present, handles nil content, handles empty messages
- **Exporter.to_markdown** — valid Markdown, message formatting, timestamp formatting, handles tool calls
- **StoreAdapter extensions** — conversation_with_stats returns computed fields, handles missing cost data

### LiveView Tests

- **Index:** mount shows table, sort columns, search filters results, tag filter, status filter, date range filter, paginate, click view navigates to show, delete removes from list
- **Show:** mount loads conversation, message thread renders with MessageComponent, metadata sidebar shows stats, inline edit title (save + cancel), inline edit tags, export JSON triggers download, export Markdown triggers download, delete redirects to index, back link works
- **Plugin:** register/2 includes conversations nav/route when enabled, excludes when disabled

### What We Don't Test

- Exact visual rendering (table styles come from PhoenixFilament's daisyUI)
- Performance under 1000+ conversations (documented limitation)
- PhoenixFilament TableRenderer internals (tested in PhoenixFilament itself)

---

## Build Order

1. **InMemoryTableLive** — generic component, independent of conversations
2. **StoreAdapter extensions** — new functions for stats computation
3. **Exporter** — standalone module, no dependencies
4. **ConversationsLive index** — table view using InMemoryTableLive
5. **ConversationsLive show** — detail view with thread + metadata
6. **Plugin integration** — register nav/route, update config default
7. **Polish** — inline edit, empty states, error handling

---

*Design approved: 2026-04-06*
*Approach: Custom LiveView + InMemoryTableLive (PhoenixFilament namespace) + Phase 1 component reuse*
