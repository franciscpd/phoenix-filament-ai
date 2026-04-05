# Architecture Patterns: phoenix_filament_ai

**Domain:** Elixir/Phoenix AI admin panel plugin
**Researched:** 2026-04-05
**Overall confidence:** HIGH (core LiveView patterns, behaviours, streaming) / MEDIUM (PhoenixFilament-specific API, PhoenixAI.Store internals — those packages have no public documentation indexed; patterns inferred from PRD + ecosystem analogues)

---

## Recommended Architecture

The plugin is a three-layer system sitting between PhoenixFilament (the panel host), PhoenixAI.Store (the persistence contract), and PhoenixAI (the AI runtime). Each layer has an explicit boundary — nothing crosses it without going through the defined interface.

```
┌──────────────────────────────────────────────────────────┐
│               PhoenixFilament Panel Host                  │
│  (routes, nav, dashboard grid, LiveSession, on_mount)    │
└────────────────────┬─────────────────────────────────────┘
                     │ Plugin behaviour: register/2, boot/1
┌────────────────────▼─────────────────────────────────────┐
│            PhoenixFilament.AI  (plugin root)              │
│                                                          │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────┐  │
│  │  Chat Layer  │  │  Data Layer   │  │  UI Layer    │  │
│  │  (streaming) │  │  (store       │  │  (widgets,   │  │
│  │              │  │   adapter)    │  │   pages)     │  │
│  └──────┬───────┘  └───────┬───────┘  └──────┬───────┘  │
│         │                  │                  │          │
└─────────┼──────────────────┼──────────────────┼──────────┘
          │                  │                  │
          ▼                  ▼                  ▼
   PhoenixAI            PhoenixAI.Store    PhoenixFilament
   (stream, converse)   (list, get, cost,  (Widget.Custom,
                         events)            layout, router)
```

---

## Component Boundaries

### 1. Plugin Root (`PhoenixFilament.AI`)

**Responsibility:** Implements the `PhoenixFilament.Plugin` behaviour. Single entry point the host panel talks to. Owns configuration validation and wires everything else together.

**Communicates with:**
- PhoenixFilament: via `register/2` return map (nav items, routes, widgets, hooks) and `boot/1` socket assigns
- `PhoenixFilamentAI.Config`: delegates option parsing
- All sub-components: referenced by module name at registration time

**Key pattern — `register/2` return contract:**
```elixir
# register/2 must return a map with known keys
%{
  nav_items: [...],    # list of nav item structs
  routes: [...],       # list of route tuples
  widgets: [...],      # list of widget module references
  hooks: [...]         # list of on_mount hook modules
}
```

**Key pattern — `boot/1` socket enrichment:**
The `boot/1` callback runs inside the panel's `live_session` `on_mount` chain. This is the correct place to inject `:ai_store` and `:ai_config` into socket assigns, making them available to every LiveView in the panel without each one fetching config individually.

```elixir
def boot(socket) do
  config = # read from panel assigns
  socket
  |> assign(:ai_store, config[:store])
  |> assign(:ai_config, config)
end
```

Confidence: MEDIUM — pattern derived from PRD + live_session/on_mount docs (HIGH confidence) + inferred register/2 contract from PhoenixFilament PRD description.

---

### 2. Config (`PhoenixFilamentAI.Config`)

**Responsibility:** Validates all plugin opts at startup using NimbleOptions. Fails fast with a clear error message if the host misconfigures the plugin.

**Communicates with:** Plugin root (called in `register/2` before anything else)

**Key pattern — compile-time schema, runtime validation:**
```elixir
@schema NimbleOptions.new!([
  store: [type: :atom, required: true],
  provider: [type: :atom, default: :openai],
  model: [type: :string, default: "gpt-4o"],
  chat_widget: [
    type: {:or, [:boolean, :keyword_list]},
    default: true,
    keys: [
      enabled: [type: :boolean, default: true],
      column_span: [type: :pos_integer, default: 6],
      # ...
    ]
  ]
])

def validate!(opts) do
  case NimbleOptions.validate(opts, @schema) do
    {:ok, config} -> config
    {:error, error} -> raise error
  end
end
```

Using `NimbleOptions.new!` at compile time means schema validation itself has no runtime cost. NimbleOptions v1.1.x supports nested `:keyword_list` with `keys:` recursively, which maps cleanly to the plugin's nested opts structure.

Confidence: HIGH — NimbleOptions official docs verified.

---

### 3. Chat Layer

Three modules with distinct roles:

#### `ChatComponent` (stateful LiveComponent)

**Responsibility:** Owns the real-time streaming state — message list, input value, streaming flag, current conversation ID. Shared between widget and page.

**Communicates with:**
- Parent LiveView (ChatWidget or ChatLive): via `send(self(), {:message_sent, ...})` for events that must bubble up
- PhoenixAI.Store: via `converse/3` which triggers the AI pipeline
- Client: via LiveView diffs on streaming assigns

**Key pattern — stateful LiveComponent over function component:**
The LiveComponent is justified here because it encapsulates both event handling (`handle_event`) AND streaming state (`handle_info` for chunks). A function component cannot hold state or receive messages. The component shares the parent LiveView's process, so `send(self(), ...)` correctly targets the parent's `handle_info`.

```elixir
defmodule PhoenixFilamentAI.Chat.ChatComponent do
  use Phoenix.LiveComponent

  def mount(socket) do
    {:ok, assign(socket, messages: [], streaming: false, current_chunk: "")}
  end

  def handle_event("send_message", %{"message" => text}, socket) do
    pid = self()
    store = socket.assigns.ai_store
    config = socket.assigns.ai_config

    Task.start(fn ->
      PhoenixAI.Store.converse(text, socket.assigns.conversation_id,
        store: store,
        on_chunk: fn chunk -> send(pid, {:ai_chunk, chunk}) end,
        on_complete: fn response -> send(pid, {:ai_complete, response}) end
      )
    end)

    {:noreply, assign(socket, streaming: true)}
  end
end
```

Confidence: HIGH — pattern verified in multiple LiveView streaming guides and LiveComponent docs.

#### `StreamHandler` (plain module)

**Responsibility:** The `handle_info` clauses that process `:ai_chunk` and `:ai_complete` messages. Extracted to a module to keep the LiveComponent/LiveView clean.

```elixir
# Used via delegation:
def handle_info({:ai_chunk, chunk}, socket), do: StreamHandler.on_chunk(chunk, socket)
def handle_info({:ai_complete, response}, socket), do: StreamHandler.on_complete(response, socket)
```

**Why extracted:** The same streaming logic applies in both the widget (ChatWidget) and the page (ChatLive). A shared module avoids duplication.

#### `ChatWidget` (Widget.Custom)

**Responsibility:** Dashboard integration. Wraps ChatComponent in PhoenixFilament's widget system to get sort, column_span, and error boundary handling.

**Communicates with:** ChatComponent (via embeds), PhoenixFilament widget grid.

#### `ChatLive` (full LiveView)

**Responsibility:** Full-screen chat page with conversation sidebar. Renders ChatComponent + ConversationSidebar. Handles navigation between conversations (pushpatch, no full reload).

---

### 4. Store Adapter (`PhoenixFilamentAI.Conversations.StoreAdapter`)

**Responsibility:** Translates CRUD vocabulary to the PhoenixAI.Store API. The only module in the plugin that calls `PhoenixAI.Store.*` for data retrieval/mutation. Everything else goes through this adapter.

**Communicates with:**
- ConversationResource, ConversationShow, ChatComponent: as data source
- PhoenixAI.Store: as delegate target

**Key pattern — hexagonal adapter with no Ecto dependency:**
The adapter pattern described in the Elixir ecosystem (Swoosh, Ecto adapters) applies directly. The adapter defines a well-bounded interface for the plugin's data needs, and PhoenixAI.Store is the only thing behind it.

```elixir
defmodule PhoenixFilamentAI.Conversations.StoreAdapter do
  @type store :: atom()
  @type conversation_id :: binary()
  @type filters :: keyword()

  @spec list(store(), filters()) :: {:ok, [map()]} | {:error, term()}
  def list(store, filters), do: PhoenixAI.Store.list_conversations(filters, store: store)

  @spec get(store(), conversation_id()) :: {:ok, map()} | {:error, :not_found}
  def get(store, id), do: PhoenixAI.Store.load_conversation(id, store: store)

  @spec update(store(), conversation_id(), map()) :: {:ok, map()} | {:error, term()}
  def update(store, id, attrs) do
    with {:ok, conv} <- PhoenixAI.Store.load_conversation(id, store: store) do
      PhoenixAI.Store.save_conversation(struct(conv, attrs), store: store)
    end
  end

  @spec delete(store(), conversation_id(), keyword()) :: :ok | {:error, term()}
  def delete(store, id, opts), do: PhoenixAI.Store.delete_conversation(id, [store: store] ++ opts)

  @spec count(store(), filters()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count(store, filters), do: PhoenixAI.Store.count_conversations(filters, store: store)
end
```

This is the only place in the plugin that knows PhoenixAI.Store's function names. If Store's API changes, only this module changes.

Confidence: HIGH — adapter pattern is established Elixir practice; specific function names are from the PRD (MEDIUM).

---

### 5. Conversation Resource (`PhoenixFilamentAI.Conversations.ConversationResource`)

**Responsibility:** Admin CRUD interface for conversations. Custom LiveView rather than a standard Ecto-backed Resource, because the data comes through StoreAdapter, not Ecto directly.

**Architecture note:** This is the most architecturally unusual component. Standard PhoenixFilament Resources assume Ecto. Since conversations come through the Store API, there are two valid approaches:

**Option A (recommended): Custom LiveView with resource-like layout**
Build a standard LiveView that implements the list/show/edit/delete pages using PhoenixFilament layout components. Less convention, more control, no Ecto contract to satisfy. This matches the Backpex pattern where custom data sources override the data-fetching layer.

**Option B: PhoenixFilament.Resource with custom data layer**
If PhoenixFilament supports a data source adapter in its Resource behaviour (like Backpex's `Backpex.Adapters.*` pattern), use it. Verify the PhoenixFilament Resource API before committing to this path — it may not be supported in v0.1.x.

Communicates with: StoreAdapter (data), PhoenixFilament layout/component library (UI).

Confidence: MEDIUM — PhoenixFilament Resource API specifics are unknown; Option A is safe regardless.

---

### 6. Cost Tracking Widgets

**Responsibility:** Three stateless widgets (stats overview, chart, top consumers) that query aggregated cost data and render read-only dashboards.

**Communicates with:** StoreAdapter (for cost queries via `PhoenixAI.Store.sum_cost/2` and `get_cost_records/2`), PhoenixFilament widget grid.

**Key pattern — stateless function component widgets:**
These widgets display read-only data and do not need event handling or streaming. They should be implemented as `Widget.Custom` modules that delegate to function components — simpler surface area, no LiveComponent overhead.

---

### 7. Event Log (`PhoenixFilamentAI.EventLog`)

**Responsibility:** Read-only audit trail with cursor-based pagination. Events are immutable, so this is a pure read path.

**Communicates with:** StoreAdapter (list_events, count_events), PhoenixFilament layout.

**Key pattern — cursor-based pagination over offset:**
Event logs grow indefinitely. Cursor-based pagination (using the last event's ID or timestamp as the cursor) avoids the performance degradation of offset pagination on large tables. The Store adapter already uses `PhoenixAI.Store.list_events/2` with cursor support.

---

### 8. Markdown Component (`PhoenixFilamentAI.Components.Markdown`)

**Responsibility:** Renders markdown strings as safe HTML in HEEx templates. Used by message components throughout the plugin.

**Key decision — MDEx over Earmark:**
Research found MDEx (built on Rust/Comrak) is 81x faster than Earmark and produces ~2,770x less memory allocation. It has built-in HTML sanitization (Ammonia), native `Phoenix.LiveView.Rendered` output, and direct HEEx component support. The PRD specifies Earmark, but MDEx should be evaluated as the actual dependency — it satisfies all the same requirements with better characteristics.

If Earmark is retained (e.g., for team familiarity), the pattern is:
```elixir
def render_markdown(content) do
  content
  |> Earmark.as_html!()
  |> HtmlSanitizeEx.html5()
  |> Phoenix.HTML.raw()
end
```

If MDEx is adopted:
```elixir
def render_markdown(content) do
  MDEx.to_html!(content, sanitize: true)
  |> Phoenix.HTML.raw()
end
```

Cache rendered HTML in the message struct's assigns — do not re-render on every diff.

Confidence: HIGH — both Earmark and MDEx patterns verified from official docs.

---

### 9. Mix Task Installer (`Mix.Tasks.PhoenixFilamentAi.Install`)

**Responsibility:** One-shot installer that patches the host app's config and panel definition. Uses Igniter for AST-safe file modification.

**Key pattern — Igniter-based installer:**
Igniter is the current standard for Phoenix ecosystem installers (used by Ash Framework, Phoenix 1.8 generators). It modifies ASTs rather than strings, handles idempotency (safe to run twice), and composes with other mix tasks.

```elixir
defmodule Mix.Tasks.PhoenixFilamentAi.Install do
  use Igniter.Mix.Task

  def igniter(igniter) do
    igniter
    |> Igniter.Project.Deps.add_dep({:phoenix_filament_ai, "~> 0.1"})
    |> add_plugin_to_panel()
    |> add_config_defaults()
    |> print_instructions()
  end
end
```

Confidence: HIGH — Igniter docs verified; pattern is current best practice (2024).

---

## Data Flow

### Streaming AI Response Flow

```
1. User submits message in ChatComponent
   └─ handle_event("send_message", ...) fires

2. Task spawned (non-blocking)
   └─ PhoenixAI.Store.converse/3 called with on_chunk callback

3. AI provider streams tokens via Finch SSE
   └─ Each chunk: on_chunk -> send(liveview_pid, {:ai_chunk, chunk})

4. handle_info({:ai_chunk, chunk}, socket) fires on LiveView process
   └─ Appends chunk to current_chunk assign
   └─ LiveView diff sent to client (token appears in UI)

5. Streaming completes: send(pid, {:ai_complete, response})
   └─ handle_info({:ai_complete, response}, socket)
   └─ Final message committed to messages list
   └─ streaming: false, current_chunk: ""
   └─ Store saves response, records cost (async in PhoenixAI pipeline)
```

**Important:** Do NOT use LiveView Streams (`stream_insert`) for token-by-token updates. LiveView Streams manages discrete list items with keyed DOM nodes. For text accumulation (appending characters to a string), direct assign updates are correct. The streaming container should use `phx-update="replace"` so the entire message bubble re-renders on each chunk, not DOM morphing per-character.

### CRUD Data Flow (Conversations Resource)

```
HTTP request → ConversationResource LiveView
  └─ mount/2: StoreAdapter.list(store, filters)
                └─ PhoenixAI.Store.list_conversations(filters, store: store)
                     └─ ETS or Ecto backend (transparent to plugin)
  └─ handle_event("delete", ...): StoreAdapter.delete(store, id, [])
  └─ handle_event("update", ...): StoreAdapter.update(store, id, attrs)
```

### Cost Dashboard Flow

```
Widget mount → StoreAdapter.sum_cost(store, period_filter)
             → StoreAdapter.cost_records(store, filters)
             → Rendered as static assigns (no streaming)
             → Periodic refresh via :timer.send_interval if live cost needed
```

---

## Suggested Build Order (Dependencies Between Components)

Dependencies flow downward — each phase only depends on what was built before.

### Phase 1 — Foundation
Build in this order within the phase:
1. `Config` (NimbleOptions schema) — no dependencies
2. `PhoenixFilament.AI` plugin root with `register/2` and `boot/1` — depends on Config
3. `Markdown` component — no dependencies, needed by messages
4. `MessageComponent` — depends on Markdown
5. `StreamHandler` — no dependencies (pure handle_info logic)
6. `ChatComponent` (LiveComponent) — depends on StreamHandler, MessageComponent
7. `ChatWidget` (Widget.Custom) — depends on ChatComponent

All Phase 2+ features depend on Phase 1 being complete (plugin must boot correctly).

### Phase 2 — Conversations Resource
Build order:
1. `StoreAdapter` — depends only on PhoenixAI.Store API (external)
2. `ConversationResource` (index + table) — depends on StoreAdapter
3. `ConversationShow` (thread view) — depends on StoreAdapter, MessageComponent (from Phase 1)

### Phase 3 — Chat Page
Build order:
1. `ConversationSidebar` component — depends on StoreAdapter
2. `ChatLive` LiveView — depends on ChatComponent (Phase 1), ConversationSidebar

### Phase 4 — Cost Dashboard
Build order:
1. Cost query additions to StoreAdapter — depends on PhoenixAI.Store cost API
2. `CostStatsWidget`, `CostChartWidget`, `TopConsumersWidget` — depend on StoreAdapter

### Phase 5 — Event Log + Installer
Build order:
1. Event query additions to StoreAdapter
2. `EventLogLive` — depends on StoreAdapter
3. `EventComponent` — depends on Markdown (Phase 1)
4. `Mix.Tasks.PhoenixFilamentAi.Install` — depends on all above being stable (versions)

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Direct PhoenixAI.Store Calls Outside StoreAdapter

**What goes wrong:** If ChatLive, ConversationResource, and cost widgets all call `PhoenixAI.Store.*` directly, every function name used from that API is scattered across 10+ call sites. When PhoenixAI.Store's API changes, every module breaks.

**Instead:** All PhoenixAI.Store calls go through StoreAdapter. One module, one change point.

---

### Anti-Pattern 2: Using LiveView Streams for Streaming AI Text

**What goes wrong:** `stream_insert` adds a new keyed item to a DOM list. Each token would appear as a new list item in the DOM, not appended to the current message bubble. The UI would show hundreds of tiny message fragments instead of one growing message.

**Instead:** Maintain `:current_chunk` as a string assign and update it per chunk. Finalize to `:messages` list when `:ai_complete` fires. Use `phx-update="replace"` on the streaming message container.

---

### Anti-Pattern 3: Ecto Dependency in Plugin

**What goes wrong:** Adding `ecto` as a direct dep means the plugin breaks (or forces Ecto as a transitive dep) when the host app uses the ETS backend of PhoenixAI.Store.

**Instead:** All data access through the StoreAdapter, which delegates to PhoenixAI.Store. The plugin never touches Ecto directly.

---

### Anti-Pattern 4: Blocking the LiveView Process During AI Calls

**What goes wrong:** Calling `PhoenixAI.Store.converse/3` synchronously in `handle_event` blocks the LiveView process. The UI freezes until the AI returns. No intermediate chunks can be processed because `handle_info` cannot run while `handle_event` is executing.

**Instead:** Spawn a Task (or use `start_async/3`) so the LiveView process is free to handle incoming `:ai_chunk` messages during the streaming response.

---

### Anti-Pattern 5: Stateful LiveComponent for Stateless Widgets

**What goes wrong:** Wrapping every widget in a LiveComponent adds unnecessary complexity and overhead when the widget only needs to display data without handling events.

**Instead:** Cost and event log widgets are function component-based. Use stateful LiveComponent only for ChatComponent where streaming state is essential.

---

## Scalability Considerations

| Concern | Current Scope (v0.1) | Future |
|---------|----------------------|--------|
| Streaming backpressure | Single user, single conversation at a time in admin panel | Multiple concurrent chats: add per-conversation GenServer for stream state |
| Cost query performance | Admin panel, low QPS | High-volume: cache aggregated cost data in ETS, refresh on interval |
| Event log size | Cursor pagination handles unbounded growth | Archiving: handled by PhoenixAI.Store, not the plugin |
| ETS store data loss | Document: use Ecto adapter in production | N/A |
| Token rendering performance | Direct assign update per chunk | If sluggish: batch chunks every 50ms with Process.send_after buffering |

---

## Component Dependency Graph

```
PhoenixFilament.AI (plugin root)
├── PhoenixFilamentAI.Config
├── Chat:
│   ├── ChatWidget  →  ChatComponent
│   │                      ├── MessageComponent  →  Markdown
│   │                      └── StreamHandler
│   └── ChatLive    →  ChatComponent
│                   →  ConversationSidebar  →  StoreAdapter
├── Conversations:
│   ├── ConversationResource  →  StoreAdapter
│   └── ConversationShow      →  StoreAdapter
│                             →  MessageComponent (reuse)
├── CostTracking:
│   ├── CostStatsWidget    →  StoreAdapter
│   ├── CostChartWidget    →  StoreAdapter
│   └── TopConsumersWidget →  StoreAdapter
├── EventLog:
│   └── EventLogLive  →  StoreAdapter
│                     →  EventComponent  →  Markdown (reuse)
└── Components:
    ├── Markdown
    ├── TypingIndicator
    ├── ToolCallCard
    └── CostBadge
```

All paths to PhoenixAI.Store run through StoreAdapter. All paths to AI streaming run through ChatComponent + StreamHandler.

---

## Sources

- Phoenix LiveView `handle_info` and stateful LiveComponent patterns: [Phoenix.LiveComponent docs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveComponent.html) — HIGH confidence
- `live_session` + `on_mount` for panel-wide assigns: [The Phoenix Files: Live Sessions](https://fly.io/phoenix-files/live-session/) — HIGH confidence
- Streaming AI with LiveView (`start_async/3` + `send(pid, {:chunk, ...})`): [Ben Reinhart: Streaming OpenAI Part III](https://benreinhart.com/blog/openai-streaming-elixir-phoenix-part-3/) + [Sean Moriarity: Streaming GPT-3](https://seanmoriarity.com/2023/02/16/streaming-gpt-3-responses-with-elixir-and-liveview/) — HIGH confidence
- NimbleOptions schema patterns: [NimbleOptions v1.1.1 docs](https://hexdocs.pm/nimble_options/NimbleOptions.html) — HIGH confidence
- Behaviour-based adapter pattern: [Writing extensible Elixir with behaviours](https://www.djm.org.uk/posts/writing-extensible-elixir-with-behaviours-adapters-pluggable-backends/) — HIGH confidence
- Igniter installer pattern: [Igniter docs](https://hexdocs.pm/igniter/readme.html) — HIGH confidence
- MDEx markdown rendering: [MDEx GitHub](https://github.com/leandrocp/mdex) — HIGH confidence
- Backpex LiveResource behaviour as reference for custom resource patterns: [Backpex.LiveResource docs](https://hexdocs.pm/backpex/Backpex.LiveResource.html) — HIGH confidence (as analogue)
- PhoenixFilament.Plugin `register/2`/`boot/1` specifics: inferred from PRD + ecosystem patterns — MEDIUM confidence (no public hexdocs found for `phoenix_filament`)
- PhoenixAI.Store function signatures: inferred from PRD — MEDIUM confidence (no public hexdocs found)
