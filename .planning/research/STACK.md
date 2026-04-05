# Technology Stack

**Project:** phoenix_filament_ai
**Researched:** 2026-04-05
**Research mode:** Ecosystem

---

## Context

`phoenix_filament_ai` is a Hex package (plugin) with a hard constraint: **zero additional JavaScript frameworks**. All UI is LiveView + HEEx. The plugin depends on `phoenix_filament`, `phoenix_ai`, and `phoenix_ai_store`. It ships as a library — not an application — so every dependency it adds becomes a transitive dependency for the host app.

This constraint narrows the stack considerably and makes it more predictable.

---

## Recommended Stack

### Runtime Dependencies (shipped with the plugin)

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| `phoenix_filament` | `~> 0.1` | Plugin host — panel UI, widgets, nav, routes | Required by the plugin contract |
| `phoenix_ai` | `~> 0.3` | AI runtime — streaming via Finch SSE, provider abstraction | Core integration target |
| `phoenix_ai_store` | `~> 0.1` | Conversation persistence, cost tracking, event log | Core integration target |
| `nimble_options` | `~> 1.1` | Config schema validation and self-documenting opts | Industry standard for Elixir library opts. v1.1.1 is current. Used by Ecto, Broadway, Oban, etc. |
| `mdex` | `~> 0.12` | Server-side Markdown to HTML with streaming fragment support | Replaces Earmark. 81x faster (Rust NIF via comrak), built-in XSS sanitization via ammonia, native LiveView HEEx integration, `streaming: true` for incomplete markdown fragments during AI token streaming. v0.12.0 is current. |

**Note on html_sanitize_ex:** MDEx ships with ammonia (Rust-based HTML sanitizer) as its sanitization layer. This makes `html_sanitize_ex` unnecessary — MDEx's `:sanitize` option handles XSS protection at render time with zero extra dependency.

**Note on contex (charts):** Contex v0.5.0 was released May 2023 and has not been updated since. It remains the only zero-JS server-side SVG charting library in the Elixir ecosystem. The cost dashboard (Phase 4) needs bar charts, pie charts, and sparklines — all of which Contex supports. Despite the maintenance pause, it is dependency-light and battle-tested. Recommend accepting the dependency but isolating chart rendering behind a module boundary so it can be swapped later. Add contex as a runtime dep only when the cost_dashboard feature is enabled.

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| `contex` | `~> 0.5` | Server-side SVG charts (bar, sparkline) for cost dashboard | Only zero-JS chart lib in the ecosystem. Stale (last release May 2023) but functional. Isolate behind a module boundary. |

### Dev / Test Dependencies (not shipped)

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| `ex_doc` | `~> 0.34` | HTML + EPUB + Markdown (llms.txt) docs generation | Standard for Hex packages. v0.40.1 is current. |
| `credo` | `~> 1.7` | Static code analysis, style consistency | v1.7.17 current. Consistent team coding style. |
| `dialyxir` | `~> 1.4` | Dialyzer type checking via mix tasks | v1.4.7 current. Catches type errors and unreachable code before runtime. |
| `excoveralls` | `~> 0.18` | Test coverage reports with coveralls.io integration | v0.18.5 current. PRD targets >80% coverage. |

### Mix Task Installer Dependency (dev + test, not shipped as runtime)

| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| `igniter` | `~> 0.7` | AST-based code patching for `mix phoenix_filament_ai.install` | v0.7.2 is current (Jan 2026). AST manipulation instead of regex/string hacks. Used by Phoenix 1.8 generators and Ash framework. Composable mix tasks. |

---

## Platform Versions

| Platform | Version | Notes |
|----------|---------|-------|
| Elixir | `~> 1.15` | Minimum for Igniter; `~> 1.17` recommended for full compat |
| Erlang/OTP | `~> 26` | Required for Elixir 1.15+ |
| Phoenix LiveView | `~> 1.1` | v1.1.28 current. Needed for colocated hooks feature |
| Phoenix | `~> 1.8` | v1.8.5 current. Required by LiveView 1.1 |

---

## Key Technology Decisions

### 1. MDEx over Earmark for Markdown

**Choose MDEx.** The PRD listed Earmark as the default choice, but MDEx is the correct choice in 2026.

**Why MDEx wins:**
- **AI streaming support**: `MDEx.new(streaming: true)` handles incomplete markdown fragments as tokens arrive. Earmark requires a complete document before parsing. This is architectural — without it, you'd need to defer all rendering until streaming completes (bad UX) or accept garbled output mid-stream.
- **Performance**: 81x faster (0.11ms vs 9ms per parse), 2770x less memory. Irrelevant for cold docs but significant when rendering every token in a streaming response.
- **XSS built-in**: ammonia (Rust) handles sanitization. No second dependency (`html_sanitize_ex`) needed.
- **Native HEEx**: `MDEx.to_heex/2` returns a `Phoenix.LiveView.Rendered` struct — no `raw/1` workaround needed, change tracking works correctly.
- **Precompiled NIF**: Ships precompiled binaries for `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`. No Rust toolchain needed in host app.

**Earmark is a pure-Elixir fallback option when:** the host app cannot accept NIF dependencies (rare constraint). Document this as a known limitation.

**Confidence:** HIGH — official docs + GitHub verified, v0.12.0 actively maintained.

### 2. handle_info for AI Streaming, Not LiveView Streams

The PRD already made this decision. Research confirms it.

**Pattern:**
```elixir
# Stream handler — called by PhoenixAI's on_chunk callback
def handle_info({:ai_chunk, chunk}, socket) do
  current = socket.assigns.streaming_content
  {:noreply, assign(socket, streaming_content: current <> chunk)}
end

def handle_info({:ai_complete, response}, socket) do
  {:noreply,
   socket
   |> assign(streaming: false, streaming_content: "")
   |> stream_insert(:messages, response)}
end
```

**Why not LiveView Streams for chunks:** LiveView Streams is for discrete list items with DOM IDs. Token-by-token appending is a string accumulation pattern — applying `stream_insert` per token sends a full DOM element diff per token (hundreds of wire messages). The `handle_info` + single assign update sends only the changed text diff. Use `phx-update="ignore"` on completed message blocks (via phoenix_streamdown pattern) to prevent re-diffing already-finished messages.

**Confidence:** HIGH — confirmed by multiple production examples and official LiveView docs.

### 3. Contex for Charts (with isolation caveat)

Contex is the only server-side SVG charting option with zero JavaScript. It covers all required chart types: bar charts, pie charts (via data series), and sparklines.

**ECharts / Chart.js are disqualified** by the zero-JS-frameworks constraint — they require JavaScript hooks and client-side rendering.

**VegaLite is disqualified** for the same reason — requires JavaScript to render the Vega specification.

**Contex limitation:** Last released May 2023, no active development. Mitigate by isolating all chart rendering in `PhoenixFilamentAI.CostTracking.Charts` — one module, one dependency surface. If Contex becomes incompatible with a future Elixir version, swap is contained.

**Confidence:** MEDIUM — Contex itself is HIGH confidence for current Elixir versions; maintenance risk is MEDIUM.

### 4. NimbleOptions for Config Validation

Industry-standard for Elixir libraries. Ecto, Broadway, Oban, Req, and the Ash framework all use it. `validate!/1` raises with clear error messages. Schema auto-generates documentation for ExDoc.

```elixir
@schema NimbleOptions.new!([
  store: [type: :atom, required: true, doc: "The PhoenixAI.Store name to use."],
  provider: [type: {:in, [:openai, :anthropic, :ollama]}, default: :openai],
  model: [type: :string, default: "gpt-4o"],
  chat_widget: [type: {:or, [:boolean, :keyword_list]}, default: true],
  # ...
])
```

**Confidence:** HIGH — v1.1.1, widely adopted, official docs verified.

### 5. Igniter for Mix Task Installer

Igniter uses Sourceror to manipulate ASTs rather than regex/string replacement. It's the modern standard for `mix *.install` tasks in the Elixir ecosystem (Phoenix 1.8, Ash, LiveView 1.1 all use it).

The installer needs to patch the host app's panel config to add the plugin declaration — exactly the AST patching use case Igniter was built for.

**Note:** Igniter must be a `dev`-only dependency in the plugin itself. It must not be a runtime dependency of host apps.

**Confidence:** HIGH — v0.7.2, official docs, active development.

---

## Alternatives Considered

| Category | Recommended | Rejected Alternative | Why Rejected |
|----------|-------------|---------------------|--------------|
| Markdown | `mdex ~> 0.12` | `earmark ~> 1.5` | No streaming support for incomplete fragments; 81x slower; no built-in XSS sanitization; no native HEEx integration |
| HTML Sanitization | Built into MDEx | `html_sanitize_ex ~> 1.4` | Redundant — MDEx/ammonia handles this |
| Charts | `contex ~> 0.5` | `vega_lite` | Requires JavaScript client rendering — violates zero-JS constraint |
| Charts | `contex ~> 0.5` | `chart_js` (via hooks) | Requires JavaScript — violates zero-JS constraint |
| Charts | `contex ~> 0.5` | `echarts` (via hooks) | Requires JavaScript — violates zero-JS constraint |
| Streaming Markdown | MDEx `streaming: true` | `phoenix_streamdown ~> 1.0.0-beta` | Beta software, additional dependency. Use MDEx streaming directly; apply `phx-update="ignore"` on completed blocks manually |
| Config Validation | `nimble_options ~> 1.1` | `norm` | NimbleOptions is ecosystem standard for library opts; Norm is for data validation schemas |
| Code Generation | `igniter ~> 0.7` | Manual EEx templates | Igniter produces idempotent AST patches; EEx templates overwrite and break on repeated installs |

---

## Installation (mix.exs for the plugin)

```elixir
defp deps do
  [
    # Runtime — shipped with the plugin
    {:phoenix_filament, "~> 0.1"},
    {:phoenix_ai, "~> 0.3"},
    {:phoenix_ai_store, "~> 0.1"},
    {:nimble_options, "~> 1.1"},
    {:mdex, "~> 0.12"},
    {:contex, "~> 0.5"},     # Only needed if cost_dashboard feature is used

    # Dev/Test — not shipped
    {:ex_doc, "~> 0.34", only: :dev, runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:excoveralls, "~> 0.18", only: :test, runtime: false},
    {:igniter, "~> 0.7", only: :dev, runtime: false}
  ]
end
```

**Optional: make contex optional** if the host app doesn't enable cost_dashboard, to avoid the dependency entirely. This requires either `optional: true` in the dep declaration or documentation telling users to add it themselves. Simpler to just include it — it's a pure Elixir library with no native code.

---

## What NOT to Use

| Library | Reason |
|---------|--------|
| `ecto` | Breaks storage-backend-agnostic contract. All data goes through PhoenixAI.Store API. |
| Any JS framework (Alpine.js, React, Vue) | Zero-JS constraint is core to the plugin's value prop |
| `html_sanitize_ex` | Redundant with MDEx/ammonia |
| `phoenix_streamdown` | Beta status; extra dependency; MDEx streaming handles the core use case |
| `vega_lite` / `kino` | Kino is Livebook-specific; VegaLite requires JavaScript |
| `earmark` | Replaced by MDEx for all reasons listed above |
| `norm` | Overkill for plugin config; NimbleOptions is the standard |
| `mox` | Use built-in ExUnit mock patterns for the Store adapter; Mox adds complexity |

---

## Confidence Summary

| Area | Confidence | Notes |
|------|------------|-------|
| Core framework (Phoenix/LiveView) | HIGH | Official docs, v1.1.28 current |
| MDEx for Markdown | HIGH | Official docs, v0.12.0, actively maintained 2026 |
| NimbleOptions for config | HIGH | Official docs, v1.1.1, ecosystem standard |
| Igniter for installer | HIGH | Official docs, v0.7.2, Jan 2026 release |
| handle_info streaming pattern | HIGH | Multiple production examples confirmed |
| Contex for charts | MEDIUM | Functional but maintenance paused May 2023 |
| PhoenixFilament plugin API | LOW | Package not yet publicly indexed on Hex; API described in PRD references local source files. Must be verified against actual source before implementation. |
| PhoenixAI / PhoenixAI.Store | LOW | Same — pre-release packages not on public Hex index. API contracts from PRD need direct source verification. |

---

## Sources

- [Phoenix LiveView v1.1.28 docs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html)
- [MDEx v0.12.0 docs](https://hexdocs.pm/mdex/MDEx.html)
- [MDEx GitHub](https://github.com/leandrocp/mdex) — streaming: true option, ammonia XSS protection
- [MDEx website](https://mdelixir.dev/) — performance benchmarks (81x vs Earmark)
- [NimbleOptions v1.1.1 docs](https://hexdocs.pm/nimble_options/)
- [Igniter v0.7.2 docs](https://hexdocs.pm/igniter/readme.html)
- [Contex v0.5.0 docs](https://hexdocs.pm/contex/Contex.html) — last release May 2023
- [Credo v1.7.17 docs](https://hexdocs.pm/credo/)
- [Dialyxir v1.4.7 docs](https://hexdocs.pm/dialyxir/readme.html)
- [ExCoveralls v0.18.5 docs](https://hexdocs.pm/excoveralls/ExCoveralls.html)
- [Phoenix LiveView 1.1 released](https://www.phoenixframework.org/blog/phoenix-liveview-1-1-released)
- [Streaming OpenAI with LiveView](https://fly.io/phoenix-files/streaming-openai-responses/)
- [phoenix_streamdown GitHub](https://github.com/dannote/phoenix_streamdown) — phx-update="ignore" pattern for streaming
- [html_sanitize_ex v1.4.3](https://hexdocs.pm/html_sanitize_ex/) — superseded by MDEx/ammonia
