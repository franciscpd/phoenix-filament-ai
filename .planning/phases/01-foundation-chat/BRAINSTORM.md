# Phase 1: Foundation + Chat — Design Spec

**Date:** 2026-04-05
**Status:** Approved
**Approach:** Risk-First build order — validate Plugin API, Store API, and streaming before building features
**Component strategy:** Layered components — MessageComponent → ChatThread → Widget/Page shells

---

## 1. Project Scaffold & Plugin Skeleton

### Package

- Name: `:phoenix_filament_ai`
- Version: `0.1.0-dev` (first release: `0.1.0-rc.1`)
- License: MIT
- Elixir version: matches `phoenix_ai`'s requirement (verify during implementation)
- Published directly on Hex (no org)

### Dependencies

**Runtime:**

| Library | Version | Purpose |
|---------|---------|---------|
| `phoenix_filament` | `~> 0.1` | Plugin host — panel UI, widgets, nav, routes |
| `phoenix_ai` | `~> 0.3` | AI runtime — streaming via Finch SSE |
| `phoenix_ai_store` | `~> 0.1` | Conversation persistence, cost tracking, event log |
| `nimble_options` | `~> 1.1` | Config schema validation |
| `mdex` | `~> 0.12` | Server-side Markdown with streaming fragment support |
| `makeup` | `~> 1.1` | Syntax highlighting for code blocks |
| `makeup_elixir` | `~> 1.0` | Elixir-specific syntax highlighting |

**Dev/Test only:** `ex_doc`, `credo`, `dialyxir`, `excoveralls`

### Plugin Module (`PhoenixFilament.AI`)

Implements `PhoenixFilament.Plugin` behaviour:

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
      hooks: build_hooks(config)  # includes copy_button hook
    }
  end

  @impl true
  def boot(socket) do
    config = get_plugin_config(socket)
    socket
    |> assign(:ai_store, config[:store])
    |> assign(:ai_config, config)
  end
end
```

### Config (`PhoenixFilamentAI.Config`)

- NimbleOptions schema covering all plugin opts from PRD §4.6
- Compile-time validation — app does not compile with invalid config
- Required: `:store`, `:provider`, `:model`
- Progressive feature defaults: `chat_widget: true`, `chat_page: true`, other features `false` until implemented
- Navigation: default group "AI", overridable via `nav_group` opt

### CI

GitHub Actions workflow:
- Matrix: Elixir versions matching supported range
- Steps: `mix test`, `mix credo`, `mix dialyzer`, `mix format --check-formatted`

### Directory Structure

```
lib/
├── phoenix_filament/
│   └── ai.ex                          # Plugin module
├── phoenix_filament_ai/
│   ├── config.ex                      # NimbleOptions schema
│   ├── store_adapter.ex               # CRUD → Store API
│   ├── chat/
│   │   ├── chat_thread.ex             # Stateful LiveComponent (streaming + messages)
│   │   ├── chat_widget.ex             # Dashboard widget shell
│   │   ├── chat_page.ex               # Full-screen LiveView
│   │   ├── sidebar.ex                 # Conversation sidebar component
│   │   └── stream_handler.ex          # Streaming logic (Task.async + to:pid, error classification)
│   └── components/
│       ├── message_component.ex       # Single message renderer
│       ├── markdown.ex                # MDEx wrapper (streaming + complete)
│       ├── tool_call_card.ex          # Collapsible tool call
│       ├── typing_indicator.ex        # "Typing..." animation
│       └── copy_button_hook.ex        # phx-hook for clipboard
test/
├── phoenix_filament_ai/
│   ├── config_test.exs
│   ├── store_adapter_test.exs
│   ├── chat/
│   │   ├── chat_thread_test.exs
│   │   ├── chat_widget_test.exs
│   │   └── chat_page_test.exs
│   └── components/
│       ├── message_component_test.exs
│       └── markdown_test.exs
└── support/
    └── fixtures.ex
```

---

## 2. StoreAdapter

### Module: `PhoenixFilamentAI.StoreAdapter`

Abstraction layer between the plugin and `PhoenixAI.Store`. Only module that knows the Store's function names — if the API changes, only this file changes.

### Public Interface

```elixir
defmodule PhoenixFilamentAI.StoreAdapter do
  # Conversations
  def list_conversations(store, filters \\ [])
  def get_conversation(store, id)
  def create_conversation(store, attrs)
  def update_conversation(store, id, attrs)
  def delete_conversation(store, id, opts \\ [])  # soft/hard via opts
  def count_conversations(store, filters \\ [])

  # Messages (lazy loading)
  def list_messages(store, conversation_id, opts \\ [])
    # opts: limit (default 20), before_cursor (for scroll-up loading)
    # returns: {messages, next_cursor}

  # Streaming
  def converse(store, conversation_id, message, opts \\ [])
    # Delegates to PhoenixAI.Store.converse/3
    # opts include streaming option: `to: pid` for PID-based streaming

  # Store info
  def backend_type(store)  # :ets | :ecto — for ETS warning banner
end
```

### Design Decisions

- All functions receive `store` as first argument (named store, e.g., `:my_store`)
- Lazy loading via cursor-based pagination: `list_messages/3` returns `{messages, next_cursor}`
- `backend_type/1` returns backend type for ETS warning
- No caching — Store is the source of truth
- Errors propagated as `{:ok, result}` / `{:error, reason}` — no exceptions
- Uses only PhoenixAI.Store public API — backend-agnostic

---

## 3. Markdown & Message Rendering

### Markdown Module (`PhoenixFilamentAI.Components.Markdown`)

Two rendering modes:

```elixir
# Complete mode — finalized messages
def render_complete(markdown_string)
  # MDEx.to_html(markdown_string, sanitize: true)
  # + Makeup syntax highlighting for code blocks

# Streaming mode — during token-by-token delivery
def render_streaming(accumulated_text)
  # MDEx with streaming: true — handles incomplete markdown
  # e.g., "**bold text" without closing → renders partially
```

- Makeup applies syntax highlighting to code blocks produced by MDEx
- XSS sanitization built-in via ammonia (inside MDEx)
- Output is `Phoenix.LiveView.Rendered` via `MDEx.to_heex/2` — change tracking works natively

### MessageComponent (`PhoenixFilamentAI.Components.MessageComponent`)

Renders a single message. Assigns: `:message`, `:streaming`, `:on_retry`.

Rendering by role:
- `:user` — slightly darker background, **markdown rendered** (same pipeline as assistant), code blocks with highlighting + copy
- `:assistant` — light background, markdown rendered, code blocks with highlighting + copy
- `:system` — highlighted banner (yellow/amber background), smaller text
- `:error` — red/rose background, error icon, retry button
- `:tool_call` — collapsible card with tool name, input JSON, output JSON

Both user and assistant messages pass through the same MDEx rendering pipeline. The only difference is visual styling (background color), not rendering.

### ToolCallCard

- Collapsed by default — shows tool name + status badge
- Expanded shows input and output formatted as JSON with syntax highlighting
- Toggle via `phx-click` (no additional JS)

### Copy Button Hook

- Only JS hook in the plugin — `navigator.clipboard.writeText()`
- Registered via `PhoenixFilament.AI` in `register/2` hooks
- Button appears on code block hover (CSS `:hover` + position absolute)

---

## 4. Streaming Pipeline

### PhoenixAI.Store Streaming API (verified 2026-04-06)

The Store's `converse/3` supports two mutually exclusive streaming modes:

| Mode | Option | Mechanism |
|------|--------|-----------|
| **Callback** | `on_chunk: fn %StreamChunk{} -> ... end` | Function called per token inside the Store's task |
| **PID** | `to: pid` | Store sends `{:phoenix_ai, {:chunk, %StreamChunk{}}}` to the target process |

Both modes return `{:ok, %Response{}}` after the stream completes. There is **no separate `on_complete` callback** — completion is the return value. Passing both `on_chunk` and `to` returns `{:error, :conflicting_streaming_options}`.

The Store persists messages, costs, and events identically for streaming and non-streaming. A `streaming: true/false` flag is included in event logs and telemetry metadata.

**StreamChunk struct:** `%PhoenixAI.StreamChunk{delta: "token text"}` — the `delta` field contains the incremental text.

### Design Decision: Use `to: pid` Mode

We use **PID-based streaming** (`to: self()`) because:

1. The LiveView process (ChatPage/ChatWidget parent) is already a GenServer that handles messages via `handle_info/2`
2. No intermediate Task needed — Store sends chunks directly to the LiveView process
3. The `on_chunk` callback runs inside the Store's internal task — `self()` inside it is NOT the LiveView PID, making it error-prone for message passing
4. Simpler error handling — Task failure is handled by the Task's monitor, not by callback exceptions

### Data Flow

```
User sends message
       │
       ▼
ChatThread receives "send_message" event
       │
       ├─ 1. Add user message to @messages (optimistic UI)
       ├─ 2. Set @streaming = true
       ├─ 3. Add placeholder assistant message (@current_response = "")
       └─ 4. Call StreamHandler.start_stream/4
              │
              └─ Spawns Task.async that calls StoreAdapter.converse/4
                 with `to: caller_pid` (the parent LiveView PID)
                 │
                 ├─ Store sends {:phoenix_ai, {:chunk, %StreamChunk{delta: "..."}}}
                 │   directly to the LiveView process (not through the Task)
                 │
                 └─ Store.converse returns {:ok, %Response{}} when stream ends
                    → Task sends {:ai_complete, response} to caller

Token by token (chunks arrive at parent LiveView via handle_info):
       │
       ▼
ChatPage/ChatWidget handle_info({:phoenix_ai, {:chunk, chunk}})
       │
       ├─ send_update(ChatThread, id: "...", ai_chunk: chunk)
       │
       ▼
ChatThread.update/2 processes :ai_chunk assign
       │
       ├─ Append chunk.delta to @current_response
       ├─ Update last assistant message content
       ├─ Re-render MessageComponent with streaming: true
       │   └─ MDEx renders partial markdown progressively
       └─ Auto-scroll to bottom (JS hook)

Complete (Task return arrives at parent LiveView):
       │
       ▼
ChatPage/ChatWidget handle_info({ref, {:ok, response}})
       │
       ├─ Process.demonitor(ref, [:flush])
       ├─ send_update(ChatThread, id: "...", ai_complete: response)
       │
       ▼
ChatThread.update/2 processes :ai_complete assign
       │
       ├─ Set @streaming = false
       ├─ Replace placeholder with final message in @messages
       ├─ Re-render with streaming: false (final MDEx pass)
       └─ Enable input field

Error (Task failure or Store error):
       │
       ▼
ChatPage/ChatWidget handle_info({ref, {:error, reason}})
       │
       ├─ Process.demonitor(ref, [:flush])
       ├─ send_update(ChatThread, id: "...", ai_error: reason)
       │
       ▼
ChatThread.update/2 processes :ai_error assign
       │
       ├─ Remove placeholder message
       ├─ Add error message with classification (retriable/fatal/domain)
       ├─ Set @streaming = false
       └─ Flash for fatal errors
```

### StreamHandler Module

**Responsibilities:** Spawns a `Task.async` that calls `StoreAdapter.converse/4` with `to: caller_pid`. Classifies errors (retriable vs fatal). Generates user-friendly error messages.

**Key detail:** The Task wraps the `converse/4` call to capture the final `{:ok, response}` or `{:error, reason}` return value. Streaming chunks bypass the Task entirely — they go directly from Store to the LiveView process via `to: caller_pid`. The Task's only role is to:
1. Hold the `converse/4` call (blocking inside the Task, non-blocking for the LiveView)
2. Forward the final result via the standard Task return mechanism (`{ref, result}`)

**Does NOT:** render anything, manage message list, touch the DOM, handle chunks (Store sends those directly).

### ChatThread as LiveComponent — Message Routing

Since `ChatThread` is a `LiveComponent` (not a LiveView), it cannot receive `handle_info` directly. The parent process (ChatPage or ChatWidget) receives all messages and routes them via `send_update/3`:

- `{:phoenix_ai, {:chunk, chunk}}` → `send_update(ChatThread, id: ..., ai_chunk: chunk)`
- Task `{ref, {:ok, response}}` → `send_update(ChatThread, id: ..., ai_complete: response)`
- Task `{ref, {:error, reason}}` → `send_update(ChatThread, id: ..., ai_error: reason)`

ChatThread's `update/2` callback must detect and process these special assigns before the normal assign merge.

### Chunk Batching

Optional performance optimization: accumulate chunks for ~50ms before re-rendering. Implemented only if needed — start without batching, add if performance requires it.

---

## 5. Chat Widget & Chat Page Layouts

### ChatWidget (Dashboard Shell)

- `use PhoenixFilament.Widget.Custom` — native dashboard grid integration
- Header: title ("AI Assistant"), refresh and new conversation buttons
- Mounts `ChatThread` as LiveComponent
- Fixed height with internal scroll
- `column_span` configurable via plugin opts (default 6)
- Empty state: suggestive prompt with 3 clickable question suggestions

### ChatPage (Full-screen LiveView)

2-column layout: Sidebar (200-250px) + main chat area.

**Sidebar (`PhoenixFilamentAI.Chat.Sidebar`):**
- Conversation list (user's conversations, or all if admin)
- Search by title, filter by tags
- Active conversation highlighted with lateral border
- "New Chat" button in footer
- Shows accumulated cost per conversation

**Main area:**
- Header: conversation title + actions (rename, delete)
- Mounts the **same `ChatThread`** component as the widget
- Navigation between conversations via `push_patch` (no full reload)

### Component Nesting

```
ChatWidget (Widget.Custom)
  └─ ChatThread (LiveComponent)
       ├─ MessageComponent × N
       │    ├─ Markdown
       │    └─ ToolCallCard (if tool call)
       ├─ TypingIndicator (when streaming)
       └─ Input area (textarea + send button)

ChatPage (LiveView)
  ├─ Sidebar (conversation list, search, filters)
  └─ Main area
       ├─ Conversation header (title + actions)
       └─ ChatThread (LiveComponent)  ← same component
            ├─ MessageComponent × N
            ├─ TypingIndicator
            └─ Input area
```

### Conversation Navigation

- `ChatPage` uses `handle_params/3` to read `conversation_id` from URL
- Changing conversations does `push_patch` (updates URL, re-mounts `ChatThread` with new ID)
- If streaming is active when user switches conversation, stream continues in background (response saved by Store); when user returns, complete response is there

---

## 6. Error Handling & Edge Cases

### Error Classification

| Error | Type | UI Action | Flash? |
|-------|------|-----------|--------|
| Timeout | Retriable | Error message with retry button | No |
| Rate limit | Retriable | Error message with retry + countdown | Yes |
| Network failure | Retriable | Error message with retry button | No |
| Invalid API key | Fatal | Error message without retry | Yes |
| Provider down | Fatal | Error message with "try later" | Yes |
| Guardrail violation | Domain | Warning message inline | No |

### Retry

Button on error message calls `StreamHandler.start_stream/3` with the same original message. No automatic retry — user decides.

### Mid-Stream Disconnect

If LiveView reconnects during streaming (e.g., user switches tab and returns), `ChatThread` in `mount/3` loads conversation from Store. If assistant response was partially saved, shows what exists. If not saved, shows last user message without response.

### Conversation Switching During Stream

1. Stream continues in background (response saved by Store)
2. `ChatThread` receives new `conversation_id` via `update/2`
3. Loads messages from new conversation
4. When user returns to previous conversation, complete response is already there

### ETS Warning Banner

- `StoreAdapter.backend_type/1` checks type during `boot/1`
- If `:ets` in production (`Mix.env() == :prod`), injects banner at top of AI pages
- Banner dismissible via `phx-click` (dismiss persists in session, not across reloads)
- Disableable via `ets_warning: false` in plugin opts

### Empty States

- Empty chat → suggestive prompt with clickable questions
- Empty sidebar (no conversations) → "Start your first conversation" + button
- Error loading conversations → error message with retry

---

## 7. Testing Strategy

### Unit Tests (fast, no external deps)

- `Config` — validates NimbleOptions rejects invalid config and accepts valid
- `Markdown` — render_complete and render_streaming produce correct HTML, XSS sanitization
- `MessageComponent` — renders each role correctly (user, assistant, system, error, tool_call)
- `ToolCallCard` — collapsed/expanded state
- `StreamHandler` — error classification (retriable vs fatal)

### Integration Tests (with PhoenixAI.Store)

- `StoreAdapter` — list, get, create, update, delete against real Store
- `StoreAdapter` — lazy loading with cursors
- `StoreAdapter` — `converse/4` with streaming callbacks

### LiveView Tests (`Phoenix.LiveViewTest`)

- `ChatThread` — send message, receive chunks via `send/2`, verify DOM updated
- `ChatThread` — empty state renders clickable suggestions
- `ChatThread` — error shows message with retry
- `ChatWidget` — mounts inside dashboard context
- `ChatPage` — sidebar lists conversations, click changes conversation (push_patch)
- `ChatPage` — search and filter in sidebar
- `Plugin` — `register/2` returns correct nav_items, routes, widgets
- `Plugin` — `boot/1` injects assigns into socket

### What We Don't Test

- Exact visual rendering (validated in parallel test app)
- Streaming performance (validated manually)
- Browser compatibility (LiveView handles this)

### Test Infrastructure

- `test/support/fixtures.ex` — helpers for creating conversations, messages, store configs
- Store configured in `test_helper.exs` with ETS backend (fast, no DB)
- Streaming tested by simulating `send(view.pid, {:phoenix_ai, {:chunk, %PhoenixAI.StreamChunk{delta: "token"}}})` — deterministic, no real AI calls
- Task completion tested by simulating `send(view.pid, {ref, {:ok, %Response{}}})` with a mock reference

---

## Build Order (Risk-First)

1. **Scaffold** — mix.exs, CI, .formatter.exs, credo config
2. **Plugin skeleton** — `register/2` + `boot/1` — validates PhoenixFilament Plugin API
3. **NimbleOptions config** — validates compile-time checking works
4. **StoreAdapter** — validates PhoenixAI.Store API
5. **MessageComponent + MDEx** — validates markdown rendering pipeline
6. **ChatThread + StreamHandler** — validates streaming pattern (Task.async + `to: pid` + handle_info routing)
7. **ChatWidget** — dashboard integration
8. **ChatPage + Sidebar** — full-screen layout
9. **Polish** — empty states, error UX, copy button, ETS warning, typing indicator

---

*Design approved: 2026-04-05*
*Approach: Risk-First build order + Layered components*
