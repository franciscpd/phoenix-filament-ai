# Research Summary: phoenix_filament_ai

**Project:** phoenix_filament_ai
**Domain:** Hex package plugin — AI-integrated admin panel for Phoenix/LiveView
**Researched:** 2026-04-05
**Confidence:** MEDIUM (HIGH for public ecosystem; LOW for private phoenix_filament/phoenix_ai packages)

---

## Executive Summary

`phoenix_filament_ai` sits at the intersection of three established concerns: Phoenix LiveView admin panels, AI streaming UIs, and Hex library authoring. The public Elixir ecosystem has mature, well-tested answers for each of these. The single major risk factor is that the three core dependencies (`phoenix_filament`, `phoenix_ai`, `phoenix_ai_store`) are pre-release packages not yet indexed on public Hex, meaning their plugin API contracts can only be verified from local source files referenced in the PRD. This is not an unusual position for an ecosystem plugin — the Ash Framework ecosystem had the same dynamic — but it means Phase 1 must start with direct source verification, not documentation.

The standard 2026 stack for this kind of package is narrow and prescriptive. The zero-JS-frameworks constraint eliminates most chart and markdown options, leaving a clean path: MDEx for markdown (active, Rust-backed, streaming for incomplete fragments), Contex for server-side SVG charts (stale but only viable option), NimbleOptions for config schema, and Igniter for the mix task installer. No surprising choices exist. The PRD's use of Earmark should be overridden in favor of MDEx — this is not a close call: MDEx handles incomplete markdown fragments during streaming (Earmark cannot), is 81x faster, includes built-in XSS sanitization via ammonia (eliminating the html_sanitize_ex dependency), and integrates natively with HEEx templates.

The most important architectural finding is around streaming: the `handle_info` + assign accumulation pattern is correct for AI token streaming, confirmed by multiple production examples. LiveView Streams are for discrete list items (completed messages); they must not be used for token-by-token text accumulation. Additionally, the `PhoenixAI.Store.converse/3` call must be dispatched to a Task or `start_async/3` — calling it synchronously in `handle_event` blocks the LiveView process for the duration of the AI response, producing a frozen UI. Both of these architectural decisions must be correct from Phase 1; retrofitting them is expensive.

---

## Key Findings

### Recommended Stack

The runtime dependency surface is intentionally minimal. Every dependency the plugin ships becomes a transitive dependency for host apps, so the bar for inclusion is high. The chosen set — `phoenix_filament`, `phoenix_ai`, `phoenix_ai_store`, `nimble_options`, `mdex`, and conditionally `contex` — covers all requirements without redundancy.

**Core technologies:**
- `mdex ~> 0.12`: Server-side markdown rendering — chosen over Earmark for streaming fragment support, 81x performance, built-in XSS sanitization, and native HEEx output. Active as of 2026.
- `nimble_options ~> 1.1`: Plugin config schema validation — ecosystem standard (Ecto, Broadway, Oban all use it). Compile-time schema, runtime validation, auto-generates ExDoc.
- `igniter ~> 0.7`: Mix task installer — AST-based patching for `mix phoenix_filament_ai.install`. Used by Phoenix 1.8 and Ash. Dev-only dep.
- `contex ~> 0.5`: Server-side SVG charts for cost dashboard — only zero-JS chart library in the Elixir ecosystem. Last released May 2023; isolate behind a module boundary.
- `handle_info` streaming pattern: Non-blocking AI token streaming via Task + `send(pid, {:ai_chunk, chunk})` — confirmed by multiple production examples as the correct LiveView approach.

**Critical version constraints:**
- Elixir `~> 1.15` minimum; `~> 1.17` recommended for full Igniter compatibility
- Phoenix LiveView `~> 1.1` (v1.1.28 current)
- Phoenix `~> 1.8` (required by LiveView 1.1)
- Pin `phoenix_filament` to exact patch version (`~> 0.1.0`) due to pre-1.0 API instability

### Expected Features

No Elixir-native AI admin panel plugin at this scope exists for direct comparison. Research drew from Filament PHP plugins, LibreChat, Retool AI, and enterprise AI observability tools (LangSmith, Langfuse).

**Must have (table stakes):**
- Token-by-token streaming — standard since ChatGPT; a non-streaming response feels broken
- Markdown rendering in AI responses — AI outputs markdown by default; without rendering, responses look like raw asterisks
- Conversation persistence — every page reload starting fresh is unacceptable
- New conversation action + conversation list/history — universal affordances in every mature AI chat interface
- System prompt configuration — developers need context-setting at the plugin level
- Typing/loading indicator and auto-scroll — without these, a 2-second wait feels like a freeze

**Should have (differentiators):**
- Cost tracking dashboard — no reviewed Filament PHP plugin includes cost visibility; critical to prevent runaway spending
- Event log / audit trail — enterprise compliance use case; LangSmith/Langfuse charge for this; built-in is rare
- Tool call visualization — collapsible cards for tool calls; critical for teams building agentic features
- Full-screen chat page with sidebar — ChatGPT-style 2-column layout; dashboard widget alone is too constrained for real work
- Conversation export (JSON + Markdown) — ChatGPT and Claude now offer this; absence is conspicuous
- Mix task installer — `mix phoenix_filament_ai.install` reduces onboarding from 20 min to <5 min

**Defer (v2+):**
- Visual RAG pipeline / document upload — a product in itself; configure at PhoenixAI layer
- Visual tool builder — developer concern, not admin UI
- Stop generation button — requires PhoenixAI to expose a cancellation API it does not currently have
- Feedback collection (thumbs up/down) — v0.2 if demand emerges
- Message branching / alternate responses — requires PhoenixAI.Store data model changes

### Architecture Approach

The plugin is a three-layer system: PhoenixFilament (panel host) → PhoenixFilament.AI (plugin root) → PhoenixAI / PhoenixAI.Store (AI runtime + persistence). Each layer boundary is explicit. The StoreAdapter is the single module that touches `PhoenixAI.Store.*` — all other modules call the adapter, never the store directly. This is the key isolation that makes backend-agnostic storage (ETS + Ecto) work and limits the blast radius when the Store API changes.

**Major components:**
1. `PhoenixFilament.AI` (plugin root) — implements PhoenixFilament.Plugin behaviour; owns `register/2` and `boot/1`; wires everything together via NimbleOptions-validated config
2. `PhoenixFilamentAI.Config` — NimbleOptions schema; compile-time schema, runtime `validate!/1` called in `register/2` only (not in callbacks)
3. `Chat.ChatComponent` (stateful LiveComponent) — owns streaming state (current_chunk, streaming flag, message list); spawns Task for AI calls; delegates stream handling to StreamHandler
4. `Chat.StreamHandler` (plain module) — `handle_info` clauses for `:ai_chunk` / `:ai_complete`; shared between ChatWidget and ChatLive
5. `Conversations.StoreAdapter` — the only module that calls `PhoenixAI.Store.*`; translates CRUD vocabulary to store API; backend-agnostic filter handling
6. `CostTracking` widgets (stateless) — function component-based; query through StoreAdapter; chart rendering isolated in `CostTracking.Charts`
7. `EventLog.EventLogLive` — read-only, cursor-based pagination using composite cursor `{inserted_at, id}`
8. `Mix.Tasks.PhoenixFilamentAi.Install` — Igniter-based AST patcher for host app panel config

### Critical Pitfalls

1. **Blocking the LiveView process with AI streaming (Phase 1)** — calling `converse/3` synchronously in `handle_event` freezes the UI for the duration of the response. Prevention: use `start_async/3` or `Task.start` to dispatch the call; the LiveView process remains free to process incoming `:ai_chunk` messages.

2. **Using LiveView Streams for token accumulation (Phase 1)** — `stream_insert` per token produces hundreds of wire messages per response and inserts each token as a new keyed DOM item. Prevention: use a `:current_chunk` string assign updated per chunk; finalize to `:messages` stream only when `:ai_complete` fires.

3. **Using `phx-update="append"` instead of LiveView Streams for message history (Phase 1)** — pre-Streams pattern with a known DOM memory leak (unbounded TextNode accumulation confirmed in phoenix_live_view issue #1078). Prevention: use LiveView Streams (`stream/3`, `stream_insert/3`) for the completed message list from day one.

4. **Assuming ETS store has the same query capabilities as Ecto (Phase 2)** — writing filters/sort in the StoreAdapter that only work against SQL. Prevention: design the adapter to filter in-process against what the `PhoenixAI.Store` API exposes; test against both backends in CI.

5. **Float arithmetic for cost aggregation (Phase 4, but data model from Phase 1)** — sub-cent token costs compound floating-point drift over thousands of records. Prevention: store costs as `Decimal` from the first record; never use `+` on cost values.

6. **API key leaking into socket assigns (Phase 1)** — storing full config in `socket.assigns.ai_config` exposes the API key in crash reports and debug pages. Prevention: strip sensitive keys in `boot/1`; only assign `store`, `model`, `provider`, feature flags to the socket.

7. **PhoenixFilament plugin API breaking changes (ongoing)** — v0.1.x is pre-release; any minor bump can change the `register/2` return shape or `boot/1` contract without a compile error. Prevention: pin to `~> 0.1.0` (exact patch); run CI against latest `phoenix_filament` weekly.

---

## Implications for Roadmap

The PRD's 5-phase structure is validated by research. The phase order matches the dependency graph exactly. The following refinements are recommended:

### Phase 1: Foundation + Chat Widget

**Rationale:** Plugin registration is the prerequisite for everything; ChatComponent is the core value prop and is reused by Phase 3; streaming architecture must be correct from the start (retrofitting is expensive).

**Delivers:** Working plugin that installs into a PhoenixFilament panel, shows a dashboard chat widget with streaming AI responses, markdown rendering, and conversation persistence.

**Implements:** Config (NimbleOptions schema), Plugin root (register/2 + boot/1), Markdown component (MDEx), MessageComponent, StreamHandler, ChatComponent (stateful LiveComponent), ChatWidget (Widget.Custom).

**Critical decisions in this phase:**
- Use MDEx (not Earmark) from day one — streaming fragment support is architectural, not swappable
- Implement `start_async/3` for AI calls — non-negotiable for responsive UI
- Use `:current_chunk` assign for streaming, LiveView Streams for completed message history
- Validate config in `register/2`, not in callbacks
- Strip sensitive opts (API key) from socket assigns in `boot/1`
- Store cost data as `Decimal` even if cost tracking is not a Phase 1 feature

**Avoids:** Pitfalls 1, 2, 3, 7, 8, 15 (all Phase 1 warnings from PITFALLS.md)

### Phase 2: Conversations Resource

**Rationale:** Conversations resource provides the data layer the chat page sidebar depends on; StoreAdapter is the riskiest module (must work with ETS and Ecto) and should be validated before Phase 3 builds on it.

**Delivers:** Admin CRUD view for conversations (index, show, delete); tool call visualization; per-message token display; conversation export (JSON + Markdown).

**Implements:** StoreAdapter, ConversationResource (custom LiveView, not standard Ecto-backed resource), ConversationShow (thread view), ToolCallCard component.

**Risk flag:** If PhoenixFilament.Resource does not support a custom data adapter pattern, this phase requires a full custom LiveView for each CRUD page rather than the standard Resource convention. Verify before starting.

**Avoids:** Pitfall 4 (ETS vs Ecto capability assumptions) — test against both backends in CI before this phase ships.

### Phase 3: Chat Page (Full-screen)

**Rationale:** Depends on ChatComponent (Phase 1) and ConversationSidebar (Phase 2 StoreAdapter). No new dependencies. Pure LiveView work with marginal cost given Phase 1 investment.

**Delivers:** Full-screen ChatGPT-style chat page with conversation sidebar; push_patch-based navigation between conversations; ETS backend warning banner.

**Implements:** ConversationSidebar, ChatLive (full LiveView embedding ChatComponent).

**Avoids:** Pitfall 12 (sidebar navigation causing full page reloads) — use `push_patch`, not `push_navigate`.

### Phase 4: Cost Dashboard

**Rationale:** Additive feature; no other phase depends on it; Contex has the highest external dependency risk (maintenance status) and should be introduced last among features.

**Delivers:** Three dashboard widgets: cost stats overview, cost chart by period/model, top consumers table.

**Implements:** Cost query additions to StoreAdapter, CostStatsWidget / CostChartWidget / TopConsumersWidget, CostTracking.Charts module (isolation boundary for Contex).

**Pre-phase check:** Validate that Contex v0.5.0 compiles with the project's Elixir/OTP versions before committing to this phase. If Contex fails, the cost chart must be a simple table — document this as a fallback in the phase plan.

**Avoids:** Pitfall 5 (float arithmetic for cost) — should be avoided from Phase 1; Pitfall 11 (SVG re-render on every poll) — fingerprint data, skip render on no change.

### Phase 5: Event Log + Mix Task Installer + Release Polish

**Rationale:** Event log is read-only infrastructure; installer is developer convenience, not a functional requirement. Both are appropriate release-prep concerns. ExDoc and Hex publishing happen here.

**Delivers:** Event log with cursor-based pagination; `mix phoenix_filament_ai.install` Igniter task; ExDoc documentation (including llms.txt); Hex package release.

**Implements:** Event query additions to StoreAdapter, EventLogLive (cursor-based pagination), EventComponent, Mix.Tasks.PhoenixFilamentAi.Install.

**Avoids:** Pitfall 10 (non-unique cursor key) — use composite cursor `{inserted_at, id}` from the first query.

### Phase Ordering Rationale

- Phase 1 first: plugin boot, ChatComponent, and streaming architecture are the critical path. Every other feature depends on plugin registration working correctly.
- Phase 2 before Phase 3: the ConversationSidebar in Phase 3 needs the StoreAdapter from Phase 2. Building the data layer before the UI that depends on it prevents a rewrite.
- Phase 4 after Phase 2/3: cost tracking is additive and has the highest external dependency risk (Contex); placing it later reduces risk to the core delivery.
- Phase 5 last: installer and docs are release prep, not feature work. Publishing to Hex before Phase 1-4 are stable would create premature public API commitments.

### Research Flags

Phases needing deeper research during planning:
- **Phase 1:** Verify `PhoenixFilament.Plugin` behaviour source before implementing `register/2` and `boot/1`. The exact return map shape and widget registration contract are inferred from the PRD — not from public docs. Also verify MDEx `streaming: true` behavior with real token streams before finalizing ChatComponent.
- **Phase 2:** Verify whether `PhoenixFilament.Resource` supports a custom data adapter (not Ecto-backed). If not, plan for full custom LiveViews from the start to avoid a mid-phase pivot.
- **Phase 4:** Validate Contex v0.5.0 compiles with Elixir 1.17+ and current OTP before starting. Check open GitHub issues for compatibility problems.

Phases with standard, well-documented patterns (research phase optional):
- **Phase 3:** Pure LiveView work; `push_patch` navigation and LiveComponent reuse are well-documented. No novel decisions required.
- **Phase 5:** Igniter installer patterns and ExDoc configuration are well-documented. Hex publishing process is standard.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack (public packages) | HIGH | MDEx, NimbleOptions, Igniter, Contex — all verified via official docs and current versions confirmed |
| Streaming architecture | HIGH | handle_info + Task pattern confirmed by multiple production examples and official LiveView docs |
| Feature priorities | MEDIUM | Derived from Filament PHP ecosystem (closest analog); no direct Elixir-native comparators exist |
| Architecture patterns | HIGH (public) / MEDIUM (private) | LiveView component patterns HIGH; PhoenixFilament.Plugin API MEDIUM (inferred from PRD) |
| Pitfalls | HIGH | Drawn from official issue tracker, official docs, and corroborated community post-mortems |
| PhoenixFilament plugin API | LOW | Pre-release, not on public Hex; API shapes from PRD only — must be verified against actual source |
| PhoenixAI / PhoenixAI.Store API | LOW | Same — pre-release, not on public Hex; function signatures from PRD; chunk shape unknown |

**Overall confidence:** MEDIUM — the public ecosystem decisions are HIGH confidence; the pre-release dependency API contracts are LOW and represent the primary project risk.

### Gaps to Address

- **PhoenixFilament.Plugin behaviour source** — actual `register/2` return type shape and `boot/1` socket structure must be verified before Phase 1 begins. The PRD describes the contract but source verification is required.
- **PhoenixAI.Store.converse/3 chunk shape** — what is the type of `chunk` in the `on_chunk` callback? String? Map with `%{content: ...}`? This affects the ChatComponent implementation directly.
- **PhoenixAI.Store cost/event API** — `sum_cost/2`, `get_cost_records/2`, `list_events/2`, `count_events/2` function signatures are assumed from the PRD. Verify against actual source before Phase 4.
- **PhoenixFilament.Resource custom data adapter** — determine in Phase 2 planning whether the Resource behaviour supports non-Ecto data sources; impacts the entire ConversationResource implementation approach.
- **Contex Elixir 1.17+ compatibility** — last released May 2023; run `mix deps.get && mix compile` against current Elixir/OTP before Phase 4 begins.
- **MDEx precompiled NIF targets** — confirm `aarch64-linux` is included for GitHub Actions ARM runners and common CI environments.

---

## Sources

### Primary (HIGH confidence)

- [Phoenix LiveView v1.1.28 docs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html)
- [MDEx v0.12.0 docs](https://hexdocs.pm/mdex/MDEx.html) + [MDEx GitHub](https://github.com/leandrocp/mdex)
- [NimbleOptions v1.1.1 docs](https://hexdocs.pm/nimble_options/)
- [Igniter v0.7.2 docs](https://hexdocs.pm/igniter/readme.html)
- [phoenix_live_view issue #1078](https://github.com/phoenixframework/phoenix_live_view/issues/1078) — `phx-update="append"` TextNode leak
- [Phoenix Files: Building a Chat App with LiveView Streams](https://fly.io/phoenix-files/building-a-chat-app-with-liveview-streams/)
- [Phoenix Files: Async processing in LiveView](https://fly.io/phoenix-files/liveview-async-task/)
- [Elixir Library Guidelines](https://hexdocs.pm/elixir/library-guidelines.html)

### Secondary (MEDIUM confidence)

- [MDEx website: performance benchmarks](https://mdelixir.dev/) — 81x vs Earmark
- [Ben Reinhart: Streaming OpenAI Part III](https://benreinhart.com/blog/openai-streaming-elixir-phoenix-part-3/)
- [Filament PHP AI plugin ecosystem](https://filamentphp.com/plugins) — feature comparison reference
- [LibreChat 2025 Roadmap](https://www.librechat.ai/blog/2025-02-20_2025_roadmap)
- [Top AI Cost Tracking Solutions (Flexprice)](https://flexprice.io/blog/top-5-real-time-ai-usage-tracking-and-cost-metering-solutions-for-startups)
- [Contex v0.5.0 docs](https://hexdocs.pm/contex/Contex.html) — last release May 2023
- [Backpex.LiveResource docs](https://hexdocs.pm/backpex/Backpex.LiveResource.html) — custom resource pattern analogue

### Tertiary (LOW confidence)

- PhoenixFilament.Plugin API — inferred from PRD; no public hexdocs found
- PhoenixAI.Store function signatures — inferred from PRD; no public hexdocs found

---

*Research completed: 2026-04-05*
*Ready for roadmap: yes*
