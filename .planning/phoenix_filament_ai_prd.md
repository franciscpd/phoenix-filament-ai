# PRD: phoenix_filament_ai

> Official PhoenixFilament plugin for PhoenixAI + PhoenixAI.Store integration.
> Turns admin panels into AI-powered interfaces with chat, cost tracking, and conversation management.

---

## 1. Overview

### What It Is

`phoenix_filament_ai` is a Hex package that works as a PhoenixFilament plugin, adding AI capabilities to the admin panel. It connects PhoenixFilament (declarative UI) with PhoenixAI (AI runtime) and PhoenixAI.Store (conversation persistence).

### Why It Exists

Today, integrating AI into a Phoenix admin panel requires:
1. Building chat LiveViews from scratch
2. Managing conversation state with `phoenix_ai_store` via code
3. Building cost and usage dashboards with manual queries
4. Configuring guardrails and memory pipelines without a visual interface

`phoenix_filament_ai` eliminates all of this with a single line:

```elixir
plugins do
  plugin PhoenixFilament.AI,
    store: :my_store,
    provider: :openai,
    model: "gpt-4o"
end
```

### Value Proposition

> From a configured `phoenix_ai_store` to a complete AI interface in the admin panel in minutes — chat with streaming, conversation history, cost dashboard, and guardrails management — all declarative and extensible via PhoenixFilament's plugin API.

---

## 2. Target Audience

| Persona | Need | How the Plugin Addresses It |
|---------|------|----------------------------|
| **Phoenix dev building SaaS** | Wants to add an AI assistant to the admin panel without custom UI | Ready-made chat widget + conversation resource |
| **Tech lead with cost concerns** | Needs visibility into AI spending | Cost tracking dashboard with charts and filters |
| **Dev already using PhoenixAI** | Wants a UI to manage persisted conversations | Conversation CRUD resource integrated with Store |
| **Compliance-focused team** | Needs an audit trail and guardrails control | Event log viewer + visual policy configuration |

---

## 3. Dependencies

```elixir
# mix.exs for phoenix_filament_ai
defp deps do
  [
    {:phoenix_filament, "~> 0.1"},
    {:phoenix_ai, "~> 0.3"},
    {:phoenix_ai_store, "~> 0.1"},

    # Dev/Test
    {:ex_doc, "~> 0.34", only: :dev, runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
  ]
end
```

### Package Relationship

```
                    ┌─────────────────────┐
                    │  phoenix_filament_ai │  ← Plugin (UI layer)
                    └──────┬──────┬───────┘
                           │      │
              ┌────────────┘      └────────────┐
              ▼                                ▼
   ┌──────────────────┐             ┌──────────────────┐
   │ phoenix_filament  │             │ phoenix_ai_store │  ← Persistence
   │  (Panel + Plugin  │             └────────┬─────────┘
   │   API)            │                      │
   └──────────────────┘             ┌─────────┘
                                    ▼
                          ┌──────────────────┐
                          │    phoenix_ai    │  ← AI Runtime
                          └──────────────────┘
```

---

## 4. Features

### 4.1 — AI Chat Widget (Dashboard)

**What:** Interactive chat widget for the admin panel dashboard. Enables AI conversations directly from the panel.

**Behavior:**
- Appears as a dashboard widget (configurable column_span)
- Token-by-token response streaming via LiveView
- Current conversation history persisted via `PhoenixAI.Store`
- "New conversation" button that creates a new conversation
- Configurable system prompt via plugin opts
- Submit via Enter, Shift+Enter for new line
- "Typing..." indicator during streaming
- Auto-scroll to latest message
- Markdown rendering in responses

**Plugin opts:**
```elixir
plugin PhoenixFilament.AI,
  store: :my_store,
  chat_widget: [
    enabled: true,
    column_span: 6,
    sort: 100,
    system_prompt: "You are a helpful admin assistant.",
    model: "gpt-4o",
    provider: :openai,
    max_tokens: 4096,
    title: "AI Assistant"
  ]
```

**Uses:** `PhoenixAI.Store.converse/3` for the full pipeline (save → memory → guardrails → AI → save → cost).

---

### 4.2 — Conversations Resource

**What:** Full CRUD resource for managing conversations persisted in `PhoenixAI.Store`.

**Pages:**
- **Index:** Table with all conversations — title, user, tags, message count, total cost, status (active/deleted), date
- **Show:** Full conversation view — formatted message thread, metadata, accumulated cost
- **Edit:** Edit conversation title and tags
- **Delete:** Soft-delete with hard-delete option for admins

**Table columns:**
| Column | Type | Sortable | Searchable | Filterable |
|--------|------|----------|------------|------------|
| Title | text | yes | yes | - |
| User | text | yes | yes | select |
| Messages | count | yes | - | - |
| Total Cost | decimal | yes | - | date_range |
| Tags | badges | - | - | select |
| Status | badge | yes | - | select |
| Created At | datetime | yes | - | date_range |

**Show page — custom renderer:**
- Chat-style message thread (user on the right, assistant on the left)
- System messages highlighted in a banner
- Tool calls displayed in collapsible cards
- Conversation metadata in a sidebar
- Per-message token usage
- Accumulated cost in the footer

**Note:** This resource does not use the standard `PhoenixFilament.Resource` with a direct Ecto schema — it implements an adapter layer that translates CRUD operations to the `PhoenixAI.Store` API (which may use ETS or Ecto internally). This requires either a custom interface or a Resource behaviour adapter.

---

### 4.3 — Cost Tracking Dashboard

**What:** Dedicated dashboard widgets for AI cost monitoring.

**Widgets:**

#### 4.3.1 — Cost Stats Overview
- Total spent (selectable period)
- Average cost per conversation
- Total tokens (input + output)
- Number of AI calls
- Trend sparkline for the last 7/30 days

#### 4.3.2 — Cost Chart
- Bar chart: spending by day/week/month
- Pie chart: distribution by provider/model
- Filters: period, provider, model, user

#### 4.3.3 — Top Consumers Table
- Table of the top N users/conversations by spending
- Columns: user, conversation count, total cost, avg cost, last activity

**Uses:** `PhoenixAI.Store.sum_cost/2`, `PhoenixAI.Store.get_cost_records/2` with filters.

---

### 4.4 — Event Log Viewer

**What:** Read-only interface for the `PhoenixAI.Store.EventLog` audit trail.

**Behavior:**
- Cursor-based paginated table with all events
- Filters by event type, user, conversation, period
- Detail view with expanded event JSON
- Event types with colored badges:
  - `conversation_created` — info (blue)
  - `message_sent` — default (gray)
  - `cost_recorded` — warning (yellow)
  - `policy_violation` — error (red)
  - `memory_trimmed` — info (blue)

**Uses:** `PhoenixAI.Store.list_events/2`, `PhoenixAI.Store.count_events/2`.

---

### 4.5 — Chat Page (Full-screen)

**What:** Dedicated chat page beyond the dashboard widget. A more complete interface for longer conversations.

**Behavior:**
- 2-column layout: conversation list sidebar + main chat area
- Sidebar:
  - User's conversation list (or all, if admin)
  - Search by title
  - Filter by tags
  - "New conversation" button
  - Active conversation indicator
- Chat area:
  - Same UI as the widget, but full-height
  - Header with conversation title + metadata
  - Button to edit title
  - Button to delete conversation
  - Option to export conversation (JSON/Markdown)
- Streaming via `PhoenixAI.Store.converse/3`
- Tool call support with inline result visualization

---

### 4.6 — Configuration via Plugin Opts

**What:** All plugin configuration is done via a keyword list in the `plugins do` block.

```elixir
plugin PhoenixFilament.AI,
  # Required
  store: :my_store,

  # Provider defaults (overridable per feature)
  provider: :openai,
  model: "gpt-4o",
  api_key: System.get_env("OPENAI_API_KEY"),

  # Feature toggles
  chat_widget: true,           # or keyword list with opts
  chat_page: true,
  conversations: true,
  cost_dashboard: true,
  event_log: true,

  # Chat opts
  chat: [
    system_prompt: "You are a helpful assistant.",
    max_tokens: 4096,
    temperature: 0.7,
    tools: [],                 # List of tool modules
    guardrails: :default,      # :default | :strict | :permissive | [policies]
    memory: :default           # :default | :aggressive | :summarize | [strategies]
  ],

  # Navigation
  nav_group: "AI",
  nav_icon: "hero-sparkles"
```

---

### 4.7 — Mix Task: Installer

**What:** `mix phoenix_filament_ai.install` sets everything up automatically.

**What it does:**
1. Verifies that `phoenix_filament` and `phoenix_ai_store` are installed
2. Adds the plugin to the existing panel
3. Generates migration if using Ecto adapter (via `mix phoenix_ai_store.gen.migration` if not present)
4. Updates config/dev.exs with defaults
5. Prints post-installation instructions

**Uses:** Igniter for AST manipulation (same pattern as `phx_filament.install`).

---

## 5. Architecture

### 5.1 — Package Structure

```
lib/
├── phoenix_filament/
│   └── ai.ex                              # Main plugin (use PhoenixFilament.Plugin)
│
├── phoenix_filament_ai/
│   ├── config.ex                          # NimbleOptions schema for plugin opts
│   │
│   ├── chat/
│   │   ├── chat_widget.ex                 # Dashboard chat widget
│   │   ├── chat_live.ex                   # Full-screen chat LiveView
│   │   ├── chat_component.ex             # Reusable chat component
│   │   ├── message_component.ex          # Individual message renderer
│   │   └── stream_handler.ex             # LiveView streaming handler
│   │
│   ├── conversations/
│   │   ├── conversation_resource.ex       # Custom conversation resource
│   │   ├── conversation_show.ex           # Custom show page (thread view)
│   │   └── store_adapter.ex              # CRUD → PhoenixAI.Store API adapter
│   │
│   ├── cost_tracking/
│   │   ├── cost_stats_widget.ex          # Stats overview widget
│   │   ├── cost_chart_widget.ex          # Chart widget
│   │   └── top_consumers_widget.ex       # Table widget
│   │
│   ├── event_log/
│   │   ├── event_log_live.ex             # Event log LiveView
│   │   └── event_component.ex            # Individual event component
│   │
│   └── components/
│       ├── markdown.ex                    # Markdown rendering in HEEx
│       ├── typing_indicator.ex            # "Typing..." indicator
│       ├── tool_call_card.ex             # Tool call card
│       └── cost_badge.ex                 # Formatted cost badge
│
├── mix/
│   └── tasks/
│       └── phoenix_filament_ai.install.ex # Mix task installer
│
test/
├── phoenix_filament_ai/
│   ├── chat/
│   │   ├── chat_widget_test.exs
│   │   ├── chat_live_test.exs
│   │   └── stream_handler_test.exs
│   ├── conversations/
│   │   ├── conversation_resource_test.exs
│   │   └── store_adapter_test.exs
│   ├── cost_tracking/
│   │   └── cost_widgets_test.exs
│   ├── event_log/
│   │   └── event_log_live_test.exs
│   └── plugin_test.exs                   # Tests register/2 and boot/1
```

### 5.2 — Plugin Registration

```elixir
defmodule PhoenixFilament.AI do
  use PhoenixFilament.Plugin

  @impl true
  def register(panel, opts) do
    config = PhoenixFilamentAI.Config.validate!(opts)

    %{
      nav_items: build_nav_items(config),
      routes: build_routes(config),
      widgets: build_widgets(config),
      hooks: build_hooks(config)
    }
  end

  @impl true
  def boot(socket) do
    config = socket.assigns.__panel__.__panel__(:plugin_opts)[__MODULE__]
    store = config[:store]

    socket
    |> assign(:ai_store, store)
    |> assign(:ai_config, config)
  end
end
```

### 5.3 — Chat Flow (Streaming)

```
User types message
       │
       ▼
ChatComponent sends "send_message" event
       │
       ▼
ChatLive/ChatWidget handle_event
       │
       ▼
PhoenixAI.Store.converse/3 called with streaming callback
       │
       ├── Save user message
       ├── Apply memory pipeline
       ├── Check guardrails ──── (violation?) ──→ Display error in chat
       ├── Call AI provider with streaming
       │     │
       │     ├── on_chunk → send(self(), {:ai_chunk, chunk})
       │     │     │
       │     │     ▼
       │     │   handle_info(:ai_chunk) → stream_insert to UI
       │     │
       │     └── complete → send(self(), {:ai_complete, response})
       │
       ├── Save assistant response
       ├── Record cost
       └── Extract LTM facts (async)
              │
              ▼
         UI updated with complete response
```

### 5.4 — Store Adapter for Resource

`PhoenixAI.Store` does not use Ecto schemas directly (it may use ETS). The `StoreAdapter` translates Resource CRUD operations to the Store API:

```elixir
defmodule PhoenixFilamentAI.Conversations.StoreAdapter do
  @doc "Translates CRUD operations to PhoenixAI.Store API"

  def list(store, filters) do
    PhoenixAI.Store.list_conversations(filters, store: store)
  end

  def get(store, id) do
    PhoenixAI.Store.load_conversation(id, store: store)
  end

  def update(store, id, attrs) do
    {:ok, conv} = PhoenixAI.Store.load_conversation(id, store: store)
    updated = struct(conv, attrs)
    PhoenixAI.Store.save_conversation(updated, store: store)
  end

  def delete(store, id, opts) do
    PhoenixAI.Store.delete_conversation(id, Keyword.merge([store: store], opts))
  end

  def count(store, filters) do
    PhoenixAI.Store.count_conversations(filters, store: store)
  end
end
```

---

## 6. UX / Interface

### 6.1 — Chat Widget (Dashboard)

```
┌─────────────────────────────────────┐
│  ✨ AI Assistant            [⟳] [+] │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────┐            │
│  │ System: You are a   │            │
│  │ helpful assistant.  │            │
│  └─────────────────────┘            │
│                                     │
│            ┌───────────────────────┐ │
│            │ How many users signed │ │
│            │ up this week?         │ │
│            └───────────────────────┘ │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ Based on the data, **142 new  │  │
│  │ users** signed up this week,  │  │
│  │ a 23% increase from last...   │  │
│  └───────────────────────────────┘  │
│                                     │
├─────────────────────────────────────┤
│ ┌─────────────────────────────┐ [→] │
│ │ Ask something...            │     │
│ └─────────────────────────────┘     │
└─────────────────────────────────────┘
```

### 6.2 — Chat Page (Full-screen)

```
┌──────────────────┬──────────────────────────────────────────┐
│  Conversations   │  Sales Analysis          [⋯] [🗑]        │
│  ─────────────── │  ──────────────────────────────────────── │
│  🔍 Search...    │                                          │
│                  │  ┌────────────────────────────────────┐   │
│  ● Sales Analy.. │  │ 🤖 Based on Q1 data, revenue grew │   │
│    Apr 5 · $0.12 │  │ by 34% compared to Q4...          │   │
│                  │  └────────────────────────────────────┘   │
│  ○ User Report   │                                          │
│    Apr 4 · $0.08 │              ┌────────────────────────┐  │
│                  │              │ What about churn rate?  │  │
│  ○ Bug Triage    │              └────────────────────────┘  │
│    Apr 3 · $0.23 │                                          │
│                  │  ┌────────────────────────────────────┐   │
│                  │  │ ● ● ● typing...                    │   │
│                  │  └────────────────────────────────────┘   │
│                  │                                          │
│  ─────────────── ├──────────────────────────────────────────┤
│  [+ New Chat]    │ ┌────────────────────────────────┐  [→]  │
│                  │ │ Ask something...               │       │
│                  │ └────────────────────────────────┘       │
└──────────────────┴──────────────────────────────────────────┘
```

### 6.3 — Cost Dashboard

```
┌────────────────┐ ┌────────────────┐ ┌────────────────┐ ┌────────────────┐
│ Total Spent    │ │ Avg/Conversation│ │ Total Tokens   │ │ AI Calls       │
│ $47.23    ↑12% │ │ $0.34     ↓5%  │ │ 2.1M     ↑18% │ │ 892      ↑15%  │
│ ▁▂▃▅▆▇████    │ │ ████▇▅▃▂▁▂    │ │ ▁▂▃▃▅▆▇███    │ │ ▁▁▂▃▅▆▇████   │
└────────────────┘ └────────────────┘ └────────────────┘ └────────────────┘

┌────────────────────────────────────┐ ┌──────────────────────────────────┐
│ Spending Over Time          [30d]  │ │ Distribution by Model            │
│                                    │ │                                  │
│  $8 ┤      ╭─╮                     │ │        ┌──────────┐              │
│  $6 ┤   ╭──╯ ╰──╮    ╭──╮         │ │    gpt-4o  62%    │              │
│  $4 ┤╭──╯       ╰────╯  ╰─╮       │ │  claude    28%    │              │
│  $2 ┤╯                     ╰──     │ │   other    10%    │              │
│  $0 ┤─────────────────────────     │ │        └──────────┘              │
│      Mon  Wed  Fri  Mon  Wed       │ │                                  │
└────────────────────────────────────┘ └──────────────────────────────────┘
```

---

## 7. Development Phases

### Phase 1 — Foundation (MVP)

**Goal:** Functional plugin with chat widget on the dashboard.

**Scope:**
- [ ] Hex package scaffold (`mix.exs`, `README.md`, CI)
- [ ] Main plugin module (`PhoenixFilament.AI`) with `register/2` and `boot/1`
- [ ] Config validation with NimbleOptions
- [ ] Reusable chat component (input, messages, streaming)
- [ ] Dashboard chat widget (`use PhoenixFilament.Widget.Custom`)
- [ ] Integration with `PhoenixAI.Store.converse/3` with streaming
- [ ] Markdown rendering in responses
- [ ] Unit and integration tests

**Deliverable:** `v0.1.0-rc.1`

---

### Phase 2 — Conversations Resource

**Goal:** Full conversation CRUD in the admin panel.

**Scope:**
- [ ] Store adapter (CRUD → PhoenixAI.Store API)
- [ ] Conversation resource with table (listing, search, filters, pagination)
- [ ] Show page with thread view (formatted messages)
- [ ] Edit (title, tags)
- [ ] Soft-delete and hard-delete
- [ ] Tool call rendering on show page
- [ ] Tests

**Deliverable:** `v0.1.0-rc.2`

---

### Phase 3 — Chat Page (Full-screen)

**Goal:** Dedicated chat interface with conversation sidebar.

**Scope:**
- [ ] Chat LiveView with 2-column layout
- [ ] Sidebar with conversation list, search, filters
- [ ] Reuse of chat component from Phase 1
- [ ] Create/delete/rename conversations
- [ ] Navigate between conversations (no reload)
- [ ] Tests

**Deliverable:** `v0.1.0-rc.3`

---

### Phase 4 — Cost Dashboard

**Goal:** Full visibility into AI costs.

**Scope:**
- [ ] Cost stats overview widget (4 cards with sparklines)
- [ ] Cost chart widget (bars by period + pie by model)
- [ ] Top consumers table widget
- [ ] Period, provider, model filters
- [ ] Tests

**Deliverable:** `v0.1.0-rc.4`

---

### Phase 5 — Event Log + Polish

**Goal:** Visual audit trail + installer + docs.

**Scope:**
- [ ] Event log LiveView with cursor-based paginated table
- [ ] Filters by type, user, conversation, period
- [ ] Detail view with expanded JSON
- [ ] Mix task installer (`mix phoenix_filament_ai.install`)
- [ ] Guides: getting started, configuration, customization
- [ ] Publish to Hex

**Deliverable:** `v0.1.0`

---

## 8. Technical Decisions

### 8.1 — Streaming via LiveView

**Decision:** Use `send(self(), {:ai_chunk, chunk})` + `handle_info` to update UI during streaming, instead of LiveView Streams.

**Rationale:** AI streaming is token-by-token (hundreds of chunks). LiveView Streams is optimized for lists of discrete items, not text append. The `handle_info` pattern with assign updates is more appropriate and is the recommended approach in PhoenixAI's cookbooks.

### 8.2 — Store Adapter vs Direct Ecto Schema

**Decision:** Create an adapter layer between the Resource CRUD and the `PhoenixAI.Store` API, instead of accessing Ecto schemas directly.

**Rationale:** `PhoenixAI.Store` supports both ETS and Ecto as backends. Accessing Ecto schemas directly would break the abstraction contract and prevent use with the ETS adapter. The adapter layer translates CRUD operations to the Store's public API.

### 8.3 — Widget.Custom vs Direct LiveComponent

**Decision:** The chat widget uses `PhoenixFilament.Widget.Custom` as its base, not a standalone LiveComponent.

**Rationale:** PhoenixFilament widgets follow a standardized system with `sort`, `column_span`, error handling, and consistent rendering. Using Widget.Custom ensures native integration with the dashboard grid.

### 8.4 — Markdown Rendering

**Decision:** Server-side Markdown rendering with `Earmark` (or similar library), with HTML sanitization.

**Rationale:** Avoids JavaScript dependencies (Alpine.js, etc.). LiveView 1.1 with HEEx can render safe HTML via `Phoenix.HTML.raw/1` after sanitization. Adds `earmark` as a plugin dependency.

### 8.5 — No Direct Ecto Dependency in the Plugin

**Decision:** The plugin does NOT declare `ecto` as a direct dependency. All data interaction goes through the `PhoenixAI.Store` API.

**Rationale:** Keeps the plugin storage-backend agnostic. If the host app uses the ETS adapter, the plugin works without Ecto.

---

## 9. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| PhoenixFilament's Plugin API is experimental (v0.1.x) | High — breaking changes could break the plugin | Pin exact phoenix_filament version; keep CI running against latest; contribute upstream fixes if needed |
| Streaming performance with many tokens | Medium — UI may become sluggish with long messages | Throttle updates (batch chunks every 50ms); use `phx-update="replace"` with key on streaming container |
| Store with ETS adapter loses data on restart | Low — known ETS limitation | Document that production should use the Ecto adapter; show warning on dashboard if ETS detected |
| Markdown rendering cost for complex content | Low — Earmark is efficient | Cache rendered HTML in assigns; only re-render new messages |
| Conversation resource doesn't follow standard Resource CRUD | Medium — may need custom LiveView instead of Resource behaviour | Accept that conversations use a custom LiveView; document as an advanced plugin example |

---

## 10. Success Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Setup time (install → working chat) | < 5 minutes | Manual testing + docs review |
| Hex downloads (first month) | 100+ | hex.pm stats |
| First token latency in chat | < 500ms (excluding provider) | Telemetry span |
| Zero additional JS frameworks | 0 | Dependency audit |
| Test coverage | > 80% | ExCoveralls |

---

## 11. Out of Scope (v0.1.x)

- Visual RAG pipeline (requires document upload UI)
- Multi-tenant cost isolation (future, when PhoenixFilament supports multi-tenancy)
- Visual tool builder (creating tools via UI)
- Visual guardrails configuration (v0.2+ — requires policy editor UI)
- Voice input/output
- Image generation
- Fine-tuning management
- Prompt marketplace

---

## 12. References

- [PhoenixFilament Plugin API](../phoenix-filament/lib/phoenix_filament/plugin.ex) — behaviour and helpers
- [PhoenixFilament Widget System](../phoenix-filament/lib/phoenix_filament/panel/widget/) — 4 widget types
- [PhoenixAI Store Converse Pipeline](../phoenix-ai-store/lib/phoenix_ai/store/converse_pipeline.ex) — full turn orchestration
- [PhoenixAI Streaming](../phoenix-ai/lib/phoenix_ai/stream.ex) — Finch SSE + chunk dispatch
- [PhoenixAI Store Cost Tracking](../phoenix-ai-store/lib/phoenix_ai/store/cost_tracking/) — recording + aggregation
- [PhoenixAI Store Event Log](../phoenix-ai-store/lib/phoenix_ai/store/event_log/) — audit trail
- [PhoenixAI Guardrails](../phoenix-ai/lib/phoenix_ai/guardrails/) — policy pipeline
- [PhoenixAI Store Memory](../phoenix-ai-store/lib/phoenix_ai/store/memory/) — context window optimization
