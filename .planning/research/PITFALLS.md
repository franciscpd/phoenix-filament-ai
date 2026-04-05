# Domain Pitfalls

**Domain:** AI admin panel plugin (Elixir/Phoenix/LiveView)
**Project:** phoenix_filament_ai
**Researched:** 2026-04-05
**Confidence:** MEDIUM-HIGH (primary sources: Phoenix LiveView docs, official Elixir guidelines, community post-mortems)

---

## Critical Pitfalls

Mistakes that cause rewrites, data loss, or major production incidents.

---

### Pitfall 1: Blocking the LiveView Process with AI Streaming

**What goes wrong:** The `PhoenixAI.Store.converse/3` call with a streaming callback runs synchronously inside the LiveView process. If it blocks — even for the duration of a single AI response — the LiveView cannot respond to any user events (input, scroll, navigation) until the stream completes. Users experience a frozen UI.

**Why it happens:** Developers wire up `handle_event("send_message", ...)` to call `converse/3` directly and return only after the stream finishes. The LiveView process is single-threaded; blocking it blocks all rendering.

**Consequences:**
- UI freezes during the entire AI response (5–30+ seconds)
- "New conversation" button unresponsive while streaming
- Sidebar navigation ignores clicks mid-stream
- Long responses degrade to the same UX as non-streaming

**Prevention:**
Use `start_async/3` (LiveView 0.20+) or `Task.async` + `send(self(), ...)` to run `converse/3` off the LiveView process. The streaming callback then sends `{:ai_chunk, chunk}` messages back to the LiveView PID, which `handle_info` processes non-blockingly. This is the pattern recommended in PhoenixAI's cookbooks and confirmed in the PRD's architectural decision section.

```elixir
# WRONG — blocks LiveView
def handle_event("send_message", %{"content" => content}, socket) do
  PhoenixAI.Store.converse(content, socket.assigns.conversation_id,
    store: socket.assigns.ai_store,
    on_chunk: fn chunk -> send(self(), {:ai_chunk, chunk}) end
  )
  {:noreply, socket}
end

# RIGHT — non-blocking
def handle_event("send_message", %{"content" => content}, socket) do
  socket = start_async(socket, :ai_stream, fn ->
    PhoenixAI.Store.converse(content, socket.assigns.conversation_id,
      store: socket.assigns.ai_store,
      on_chunk: fn chunk -> send(self(), {:ai_chunk, chunk}) end
    )
  end)
  {:noreply, assign(socket, :streaming, true)}
end
```

**Warning signs:** UI freezes on message submit; "typing..." indicator appears only after response completes; LiveView telemetry shows `handle_event` duration matching response time.

**Phase mapping:** Phase 1 (Foundation) — the streaming architecture must be correct from the first implementation. Retrofitting non-blocking streaming after the fact requires rethinking the entire chat flow.

---

### Pitfall 2: Storing Full Conversation History in Socket Assigns

**What goes wrong:** Keeping all messages for the current conversation in `socket.assigns.messages` (as a list). In long conversations (100+ messages), this occupies significant server memory multiplied by the number of connected clients. With AI responses regularly containing thousands of tokens, individual messages can be large.

**Why it happens:** The simplest implementation just appends new messages to a list. It works fine in development with short conversations. In production with many users, it degrades.

**Consequences:**
- High memory per LiveView process (each user connection holds the full history)
- Garbage collection pressure on the BEAM
- Slow diffs sent over WebSocket as the list grows
- Potential OOM crashes under moderate load

**Prevention:**
Use one of two approaches, selected based on what the component actually needs:

1. For the **chat widget** (dashboard): keep only the last N messages (e.g., 20) in assigns. Older messages exist in the store and are not displayed in the widget.
2. For the **chat page** (full-screen): use LiveView Streams (`stream/3`, `stream_insert/3`) to manage the displayed message list. The server holds no in-memory copy of the stream — it lives in the client DOM.

Important nuance: LiveView Streams are for the **list of discrete messages** (one item = one complete message). The **token accumulation for the in-progress AI response** is still an assign, but it's a single string that gets replaced on each chunk, not a growing list.

**Warning signs:** Memory per connected socket growing over time; `handle_info(:ai_chunk, ...)` sends increasing diff sizes; profiling shows message list as largest assign.

**Phase mapping:** Phase 1 (Foundation) — design the message list data model correctly upfront. Phase 3 (Chat Page) requires Streams for the sidebar conversation list too.

---

### Pitfall 3: Using `phx-update="append"` Instead of LiveView Streams for Message History

**What goes wrong:** Reaching for `phx-update="append"` on the message container to add new messages without re-rendering the whole list. This is a pre-Streams pattern (pre-LiveView 0.19) with a known memory leak: extra TextNodes accumulate in the DOM with each update, causing the browser tab to slow and eventually crash under long conversations.

**Why it happens:** `phx-update="append"` is well-documented in older tutorials (pre-2023) and appears simpler than Streams. Developers who learned LiveView before 0.19 default to it.

**Consequences:**
- DOM node memory leak in the browser (unbounded TextNode accumulation)
- Browser tab performance degrades with conversation length
- Incompatible with future Streams-based features (scroll anchoring, virtualization)
- GitHub issue #1078 in phoenix_live_view confirms the leak is intentional-by-design, not a bug to be fixed

**Prevention:**
Use LiveView Streams (`stream(:messages, initial_messages)` in `mount/3`, `stream_insert(socket, :messages, new_message)` for new messages). This is the current blessed approach. Never use `phx-update="append"` for collections.

**Warning signs:** Browser `performance.memory.usedJSHeapSize` growing linearly with conversation length; browser DevTools shows increasing TextNode count.

**Phase mapping:** Phase 1 (Foundation) — if `phx-update="append"` is used in the first implementation, it will be discovered in Phase 3 load testing. Fix in Phase 1.

---

### Pitfall 4: Assuming the Store Adapter Has the Same Query Capabilities as Ecto

**What goes wrong:** Writing the `StoreAdapter` (conversations resource) with filter and sort logic that assumes an Ecto-backed store, then discovering that the ETS adapter doesn't support those operations at the `PhoenixAI.Store` API level. The plugin is supposed to be backend-agnostic.

**Why it happens:** The developer mentally models the store as "basically Ecto" and writes `list_conversations` filters expecting SQL-like semantics. ETS has no query language — filtering must happen in-process after fetching all records.

**Consequences:**
- Plugin breaks with the ETS adapter when filtering or sorting
- "Backend-agnostic" promise is violated — actual requirement is Ecto
- Users with dev/test ETS stores see different behavior than production Ecto stores
- Discovered late, when integration testing against the ETS adapter

**Prevention:**
Treat the `PhoenixAI.Store` API as the only interface — never assume backend capabilities. Design `StoreAdapter` to operate only on what the store's public API exposes. If `PhoenixAI.Store.list_conversations/2` doesn't support a given filter in all backends, implement that filter client-side (in the adapter) as an in-memory pass over the results. Document which filters may be slow on the ETS adapter (full scan vs. indexed).

**Warning signs:** Adapter code that casts filter values to Ecto query fragments; filter behavior differing between test suite (ETS) and integration test app (Ecto).

**Phase mapping:** Phase 2 (Conversations Resource) — the adapter must be tested against both backends in CI before Phase 2 ships.

---

### Pitfall 5: Using Float Arithmetic for Cost Aggregation

**What goes wrong:** Storing token costs as Elixir `float` values and accumulating them with float arithmetic. Binary floating-point cannot represent most decimal fractions exactly. After thousands of additions, the aggregate total diverges from reality. This is especially pronounced with sub-cent token costs (e.g., $0.000001 per token).

**Why it happens:** Cost values from AI provider APIs arrive as JSON floats. The path of least resistance is to store them as Elixir floats and sum them with `Enum.sum/1`.

**Consequences:**
- Dashboard totals are wrong — sometimes by cents, sometimes by dollars over high-volume use
- Per-user cost attribution diverges from actual billing
- Debugging is difficult because each individual cost looks correct; the error compounds over aggregations

**Prevention:**
Use the `Decimal` library (already a transitive dependency via Ecto/Postgrex for Ecto backends). Store costs as `Decimal` structs in memory and as `numeric` in Postgres. When receiving float values from the API, convert immediately: `Decimal.from_float(0.000234)` or `Decimal.new("0.000234")` from the string representation. Use `Decimal.add/2`, `Decimal.mult/2` for all arithmetic. Never use `+` on cost values.

**Warning signs:** Cost totals in the dashboard that round differently than `Enum.sum/1` of displayed per-message costs; test cases with many small costs that fail on equality checks.

**Phase mapping:** Phase 4 (Cost Dashboard) — but the cost data model must be established in Phase 1 when `PhoenixAI.Store.converse/3` first records costs. Fix the type before any aggregation code is written.

---

## Moderate Pitfalls

---

### Pitfall 6: Auto-Scroll Fighting User Scroll Position During Streaming

**What goes wrong:** The chat component auto-scrolls to the bottom on every token chunk. If the user scrolls up to re-read earlier content mid-stream, the auto-scroll snaps them back down 5–10 times per second. This is one of the most complained-about UX problems in chat interfaces.

**Why it happens:** The naive implementation attaches a JS hook that calls `scrollTop = scrollHeight` in the `updated` callback, which fires on every LiveView patch.

**Consequences:**
- Users cannot read previous messages while the AI is responding
- Particularly bad with long AI responses
- Users associate the frustration with the plugin, not the implementation detail

**Prevention:**
Track whether the user has manually scrolled up (using `scrollTop + clientHeight < scrollHeight - threshold`). Only auto-scroll if the user is already at the bottom, or if the message just started (first chunk). A small hook of ~15 lines handles this correctly. Also consider the CSS `flex-direction: column-reverse` trick — it keeps the scroll position at the bottom naturally without JS for new messages, though it requires reverse DOM order.

**Warning signs:** Any chat component that calls `scrollIntoView()` or `scrollTop = scrollHeight` unconditionally in the `updated` hook.

**Phase mapping:** Phase 1 (Foundation) — implement the scroll guard in the initial chat component. Easy to add upfront; annoying to retrofit after users report it.

---

### Pitfall 7: Rendering AI Markdown Without HTML Sanitization

**What goes wrong:** Passing AI-generated text through `Earmark.as_html!/1` and wrapping the result in `Phoenix.HTML.raw/1` without sanitization. While AI providers don't inject malicious HTML intentionally, tool call results (which may include user-supplied data), prompt injections, or future model outputs could embed script tags or event handlers. `raw/1` bypasses Phoenix's automatic HTML escaping.

**Why it happens:** Developers see that Earmark produces "safe" HTML from markdown and assume no further sanitization is needed. The risk seems theoretical.

**Consequences:**
- XSS vectors if any user-controlled content reaches the chat (tool call results, conversation titles, user messages rendered with markdown)
- Particularly dangerous in an admin panel where users have elevated trust

**Prevention:**
Always pipe Earmark output through an HTML sanitizer before `raw/1`. Use `HtmlSanitizeEx` with the `html5` profile, or consider `MDEx` which has built-in configurable sanitization. The pipeline is: `content |> Earmark.as_html!() |> HtmlSanitizeEx.html5() |> raw()`. Add `html_sanitize_ex` as a dependency.

**Warning signs:** Any `raw(Earmark.as_html!(content))` call in any template file.

**Phase mapping:** Phase 1 (Foundation) — sanitization must be in the initial `markdown.ex` component. Never ship raw unsanitized markdown rendering.

---

### Pitfall 8: Plugin Config Validated Too Late (Runtime Instead of Boot)

**What goes wrong:** The NimbleOptions schema for plugin opts is validated inside `handle_event` or `mount` callbacks instead of in `register/2`. Invalid config (missing `:store`, wrong `:model` format) surfaces as cryptic runtime errors in production rather than clear boot-time failures.

**Why it happens:** Config validation is often added incrementally. Early implementations check opts lazily when first needed.

**Consequences:**
- Misconfigured plugins appear to "work" during development (opts may be satisfied by defaults) but fail in production with specific opts
- Error messages point to LiveView internals, not the misconfigured plugin opt
- `boot/1` runs on every socket connect — validation overhead at connection time

**Prevention:**
Call `PhoenixFilamentAI.Config.validate!/1` in `register/2`, not later. Validation fails at application boot (or panel initialization) with a clear error message. The compiled NimbleOptions schema (`NimbleOptions.new!/1`) should be a module attribute, not recompiled per call. Any opt that must be resolved at runtime (e.g., `api_key: System.get_env(...)`) should be validated for presence in `register/2` and accessed in `boot/1`.

**Warning signs:** `NimbleOptions.validate/2` called inside `mount/3` or any callback; no validation in `register/2`.

**Phase mapping:** Phase 1 (Foundation) — `Config.validate!/1` must be wired into `register/2` before any other feature is built.

---

### Pitfall 9: Experimental Plugin API Breaking Changes Mid-Development

**What goes wrong:** `phoenix_filament` is v0.1.x — the Plugin API (`register/2` callback shape, `boot/1` socket structure) is experimental. An upstream minor version bump (0.1.x → 0.1.y) may change the contract: the return map shape from `register/2`, how widgets are registered, the assigns set by `boot/1`. This silently breaks the plugin without a compile error.

**Why it happens:** The plugin depends on `phoenix_filament` with `~> 0.1` (pessimistic constraint). Under SemVer for pre-1.0 packages, any minor version can include breaking changes. The Elixir library guidelines explicitly state that pre-1.0 packages provide no guarantees about what might change.

**Consequences:**
- Plugin stops working after host app upgrades `phoenix_filament`
- Failures are runtime, not compile-time (behaviour callbacks are duck-typed)
- Debugging requires diff-ing what `register/2` is expected to return

**Prevention:**
Pin to exact patch version: `{:phoenix_filament, "~> 0.1.0"}` (includes patch, restricts to 0.1.x). Run CI against the latest `phoenix_filament` on a weekly schedule (not just on commits) to detect upstream breaks early. Watch the `phoenix_filament` changelog. Contribute upstream if a breaking change is discovered — this plugin will be the most thorough external user of the Plugin API.

**Warning signs:** Unpinned `"~> 0.1"` in mix.exs; no upstream-tracking CI job.

**Phase mapping:** Phase 1 (Foundation) — pin the dependency correctly in the initial mix.exs. Set up the upstream-tracking CI job before Phase 2.

---

### Pitfall 10: Cursor-Based Pagination on Event Log Without Stable Sort Cursor

**What goes wrong:** Implementing cursor-based pagination on the event log using `inserted_at` timestamp as the cursor. If multiple events are inserted within the same millisecond (bulk import, fast AI pipelines), two records share the same cursor value. Pagination produces duplicate rows or skips records at the boundary.

**Why it happens:** Timestamp is the obvious cursor for an audit log sorted by recency. Developers don't account for sub-millisecond concurrency in high-throughput pipelines.

**Consequences:**
- Event log misses records during pagination (silent data gaps)
- Duplicate events appear across page boundaries
- The ETS backend may have even less cursor stability than Postgres (no guaranteed ordering within a microsecond)

**Prevention:**
Use a composite cursor: `{inserted_at, id}` where `id` is a UUID or monotonic integer. The query becomes `WHERE (inserted_at, id) > ($cursor_time, $cursor_id)`. This gives strict total ordering even with concurrent inserts. Alternatively, use a monotonic event sequence number if `PhoenixAI.Store.EventLog` provides one.

**Warning signs:** Cursor implemented as a single datetime value; no uniqueness guarantee on the sort key.

**Phase mapping:** Phase 5 (Event Log) — design the cursor structure before writing the first query.

---

## Minor Pitfalls

---

### Pitfall 11: SVG Chart Re-rendering on Every Poll

**What goes wrong:** The cost dashboard widgets re-render their SVG charts on every timer tick (e.g., every 30 seconds). With Contex or a similar server-side SVG library, re-rendering a complex chart with many data points is not free — it generates a large SVG string, diffs it against the previous one, and sends the full diff over WebSocket (SVG diffs are large because element IDs change with data).

**Why it happens:** Adding a `:timer.send_interval/2` in `mount/3` is the standard pattern for live dashboards. The entire widget re-renders on each tick.

**Prevention:**
Only re-render charts when data actually changes. Track a data fingerprint (hash of the last-fetched cost data) in assigns. Skip the chart re-render if the fingerprint matches. For static reporting periods (e.g., "last 30 days"), data changes at most once per minute — polling every 30s with a conditional skip is sufficient.

**Phase mapping:** Phase 4 (Cost Dashboard).

---

### Pitfall 12: Conversation Navigation Causing Full Page Reloads

**What goes wrong:** Navigating between conversations in the chat page sidebar triggers `phx-navigate` or a full `redirect/2`, causing a full LiveView mount cycle and a blank flash before messages load. This is particularly bad during streaming — navigating away tears down the in-progress stream.

**Why it happens:** Sidebar items are `<.link navigate={...}>` (patch vs navigate confusion).

**Prevention:**
Use `phx-patch` (`push_patch/2`) for sidebar conversation switching. The LiveView stays mounted; only `handle_params/3` runs to load the new conversation. Guard against navigating away mid-stream by disabling sidebar links (or showing a confirmation dialog) while `socket.assigns.streaming` is true.

**Phase mapping:** Phase 3 (Chat Page).

---

### Pitfall 13: Missing `running` Guard on Chat Input

**What goes wrong:** The chat form doesn't disable the submit button or input while streaming. A user who clicks "Send" twice submits two concurrent AI requests against the same conversation. The second request starts while the first stream is in progress, causing interleaved chunks and corrupted conversation state in the store.

**Why it happens:** Adding a `disabled` attribute to the form submit button is often forgotten in the first implementation.

**Prevention:**
Track streaming state in assigns (`streaming: false` in `mount/3`, set to `true` on send, back to `false` on `{:ai_complete, _}` or `{:ai_error, _}`). Use `phx-submit-loading` (LiveView built-in) or `disabled={@streaming}` on the input and button.

**Phase mapping:** Phase 1 (Foundation).

---

### Pitfall 14: ETS Backend Silent Data Loss on Node Restart

**What goes wrong:** A developer configures their test app with the ETS store adapter, builds and tests the plugin, and assumes production is covered. They don't notice that ETS tables are wiped on every BEAM restart. Production deployments lose all conversation history on every deploy.

**Why it happens:** ETS limitations are documented but easy to miss. The plugin works identically with ETS and Ecto during development.

**Prevention:**
Detect the ETS backend at `boot/1` time and surface a prominent warning on the admin dashboard. The PRD explicitly lists this as a known risk with the mitigation: "show warning on dashboard if ETS detected." Implement this warning in Phase 1 alongside the first boot logic. The warning should explain the data loss risk and link to configuration docs for the Ecto adapter.

**Phase mapping:** Phase 1 (Foundation) — the backend detection and warning is a boot-time concern.

---

### Pitfall 15: API Key Leaking into LiveView Assigns or Logs

**What goes wrong:** The plugin opts include `api_key: System.get_env("OPENAI_API_KEY")`. If `config` is passed to `boot/1` and assigned to `socket.assigns.ai_config`, the API key is present in every LiveView socket's assigns for the session duration. Phoenix LiveView debug pages, telemetry tools, and crash reports may log the full assigns map.

**Why it happens:** Storing the full config in assigns is the convenient path from `boot/1`.

**Prevention:**
Strip sensitive keys from the config before assigning to socket. In `boot/1`, store only the keys needed by LiveView components (`store`, `model`, `provider`, feature flags). Keep the API key in application config or a runtime module attribute accessible to the AI call layer, never in socket assigns.

**Phase mapping:** Phase 1 (Foundation) — the `boot/1` implementation must exclude sensitive opts from assigns.

---

## Phase-Specific Warnings

| Phase | Topic | Likely Pitfall | Mitigation |
|-------|-------|----------------|------------|
| Phase 1 | Chat streaming architecture | Blocking LiveView process (Pitfall 1) | Use `start_async/3`; test UI responsiveness during stream |
| Phase 1 | Message list data model | Socket memory growth (Pitfall 2) | Use LiveView Streams or bounded assign for message history |
| Phase 1 | Markdown rendering | XSS via unsanitized `raw/1` (Pitfall 7) | Always pipe through `HtmlSanitizeEx` |
| Phase 1 | Config validation timing | Late validation errors (Pitfall 8) | Validate in `register/2`, not in callbacks |
| Phase 1 | boot/1 assigns | API key in socket assigns (Pitfall 15) | Strip sensitive opts before assigning |
| Phase 1 | Cost data type | Float arithmetic drift (Pitfall 5) | Use `Decimal` from the first cost record |
| Phase 2 | Store adapter | ETS vs Ecto capability assumptions (Pitfall 4) | Test against both backends in CI |
| Phase 3 | Conversation switching | Full page reload on sidebar click (Pitfall 12) | Use `phx-patch`, not `phx-navigate` |
| Phase 4 | Chart refresh | SVG re-render on every poll (Pitfall 11) | Fingerprint data, skip render on no change |
| Phase 5 | Event log pagination | Non-unique cursor key (Pitfall 10) | Use composite cursor `{inserted_at, id}` |
| Ongoing | Dependency | Plugin API breaking changes (Pitfall 9) | Pin exact patch version; weekly upstream CI |

---

## Sources

- [Streaming OpenAI in Elixir Phoenix Part III — Ben Reinhart](https://benreinhart.com/blog/openai-streaming-elixir-phoenix-part-3/) — MEDIUM confidence (community blog, verified against LiveView docs)
- [Building a Chat App with LiveView Streams — The Phoenix Files](https://fly.io/phoenix-files/building-a-chat-app-with-liveview-streams/) — HIGH confidence (official Fly.io Phoenix team blog)
- [Async processing in LiveView — The Phoenix Files](https://fly.io/phoenix-files/liveview-async-task/) — HIGH confidence (official)
- [The Ten Biggest Mistakes Made With Phoenix LiveView — Hex Shift](https://hexshift.medium.com/the-ten-biggest-mistakes-made-with-phoenix-liveview-and-how-to-fix-them-cbe2afda4c36) — MEDIUM confidence (community, corroborated by official docs)
- [LiveView Assigns: Three Common Pitfalls — AppSignal Blog](https://blog.appsignal.com/2022/06/28/liveview-assigns-three-common-pitfalls-and-their-solutions.html) — MEDIUM confidence (community, corroborated by LiveView docs)
- [DOM Node memory leak with phx-update=append — GitHub Issue #1078](https://github.com/phoenixframework/phoenix_live_view/issues/1078) — HIGH confidence (official issue tracker)
- [Phoenix LiveView docs — start_async](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html) — HIGH confidence (official docs)
- [Library guidelines — Elixir](https://hexdocs.pm/elixir/library-guidelines.html) — HIGH confidence (official)
- [Sanitizing HTML with HtmlSanitizeEx — ElixirCasts](https://elixircasts.io/sanitizing-html-with-htmlsanitizeex) — MEDIUM confidence
- [NimbleOptions docs](https://hexdocs.pm/nimble_options/NimbleOptions.html) — HIGH confidence (official docs)
- [Cursor-based pagination for Elixir Ecto — paginator](https://github.com/duffelhq/paginator) — MEDIUM confidence
- [Elixir library guidelines on pre-1.0 versioning](https://hexdocs.pm/elixir/library-guidelines.html) — HIGH confidence (official)
- [MDEx — Fast and Extensible Markdown for Elixir](https://mdelixir.dev/) — MEDIUM confidence
