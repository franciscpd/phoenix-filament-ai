# Phase 1: Foundation + Chat - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Plugin boots with `register/2` and `boot/1`. Dashboard chat widget and full-screen chat page both work with token-by-token streaming, MDEx markdown rendering, and conversation persistence via PhoenixAI.Store. StoreAdapter handles all CRUD operations against the Store API (both ETS and Ecto backends). Hex package scaffolded with mix.exs, CI, and dev tooling.

</domain>

<decisions>
## Implementation Decisions

### Chat UX
- **D-01:** Full-width message blocks (not bubbles) — alternating background per sender, like ChatGPT/Claude UI
- **D-02:** Progressive markdown rendering during streaming — text appears token-by-token with markdown rendered progressively via MDEx `streaming: true`
- **D-03:** Widget column_span configurable via plugin opts, default 6 cols (half-width)
- **D-04:** Widget has fixed height with internal scroll — consistent with dashboard grid, doesn't push other widgets
- **D-05:** Empty chat state shows suggestive prompt with 2-3 clickable question suggestions
- **D-06:** AI errors (rate limit, timeout) shown inline in chat thread as error message with retry button, PLUS flash notification for critical errors (invalid API key, rate limit)
- **D-07:** Code blocks have syntax highlighting via Makeup (server-side, no JS)
- **D-08:** Code blocks have a "Copy" button via phx-hook (minimal JS, only for clipboard API)

### Plugin Configuration
- **D-09:** Progressive feature defaults — features enabled by default only as they are implemented (Phase 1: chat_widget + chat_page on; later features off until their phase ships)
- **D-10:** Config validation at compile time via NimbleOptions — app does not compile with invalid config, clear error messages
- **D-11:** Navigation configurable — default nav group "AI", but overridable via `nav_group` opt
- **D-12:** Visual configuration UI is out of scope for v0.1.x — all config via code in `plugins do` block

### API Key Handling
- **D-13:** Claude's discretion — choose the most idiomatic approach for the Elixir ecosystem (likely delegate to PhoenixAI config, with optional convenience override in plugin opts)

### Store Adapter
- **D-14:** Claude's discretion on backend-awareness strategy — use PhoenixAI.Store public API only, adapt if needed based on actual API capabilities
- **D-15:** Lazy loading for conversation messages — load last N messages initially, scroll-up loads more (better for long conversations)
- **D-16:** ETS backend warning banner configurable — shown by default when ETS detected in production, disableable via `ets_warning: false` opt

### Project Scaffold
- **D-17:** MIT license
- **D-18:** Elixir version minimum matches phoenix_ai's requirement — verify during implementation
- **D-19:** GitHub Actions CI with mix test, credo, dialyzer, format check
- **D-20:** Published as `:phoenix_filament_ai` directly on Hex (no org)
- **D-21:** Claude's discretion on test app location (separate repo vs subdir)
- **D-22:** Initial version 0.1.0-dev, first release 0.1.0-rc.1

### Claude's Discretion
- API key handling approach (D-13)
- Store adapter backend-awareness strategy (D-14)
- Test app structure (D-21)
- Loading skeleton design
- Exact spacing and typography
- Auto-scroll implementation details
- Streaming chunk batching/throttling strategy

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Plugin API
- `.planning/phoenix_filament_ai_prd.md` §5 — Architecture section with plugin registration, chat flow, and store adapter patterns
- `.planning/phoenix_filament_ai_prd.md` §4.6 — Full configuration opts specification

### Chat UX
- `.planning/phoenix_filament_ai_prd.md` §4.1 — Chat widget behavior and plugin opts
- `.planning/phoenix_filament_ai_prd.md` §4.5 — Full-screen chat page behavior
- `.planning/phoenix_filament_ai_prd.md` §6.1 — Chat widget wireframe
- `.planning/phoenix_filament_ai_prd.md` §6.2 — Chat page wireframe

### Streaming Architecture
- `.planning/phoenix_filament_ai_prd.md` §5.3 — Chat flow diagram (streaming pipeline)
- `.planning/phoenix_filament_ai_prd.md` §8.1 — Streaming via handle_info decision
- `.planning/research/STACK.md` — MDEx recommendation, handle_info pattern, Makeup for syntax highlighting

### Store Adapter
- `.planning/phoenix_filament_ai_prd.md` §5.4 — Store adapter code example
- `.planning/phoenix_filament_ai_prd.md` §8.2 — Store adapter vs direct Ecto decision
- `.planning/research/ARCHITECTURE.md` — StoreAdapter as hexagonal adapter pattern
- `.planning/research/PITFALLS.md` — ETS vs Ecto backend pitfalls

### Technical Decisions
- `.planning/phoenix_filament_ai_prd.md` §8 — All technical decisions (streaming, store adapter, widget, markdown, no Ecto dep)
- `.planning/research/STACK.md` — Full stack recommendations with versions

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- No existing code — this is a greenfield Hex package

### Established Patterns
- PhoenixFilament plugin behaviour: `register/2` returns nav_items, routes, widgets, hooks; `boot/1` injects socket assigns
- PhoenixAI.Store API: `converse/3` for streaming pipeline, `list_conversations/2`, `load_conversation/2`, etc.
- Widget system: `PhoenixFilament.Widget.Custom` for dashboard grid integration

### Integration Points
- Plugin registered via `plugins do` block in PhoenixFilament panel
- Store configured as a named store (`:my_store`) in the host app
- Streaming callback wired through `send(self(), {:ai_chunk, chunk})` + `handle_info`

</code_context>

<specifics>
## Specific Ideas

- Message layout inspired by ChatGPT/Claude — full-width blocks, not bubbles
- Empty state should feel inviting — "Ask anything about your panel" with clickable suggestions
- Code blocks should be practical — syntax highlighting AND copy button for admin users who need to grab code snippets
- ETS warning should be helpful, not annoying — configurable so devs can dismiss it

</specifics>

<deferred>
## Deferred Ideas

- **Visual configuration UI** — Interface to configure plugin via UI instead of code. Out of scope for v0.1.x, potential v0.2+ feature.
- **Stop generation button** — Requires PhoenixAI cancellation API that doesn't exist yet
- **Message editing/regeneration** — v2 feature

</deferred>

---

*Phase: 01-foundation-chat*
*Context gathered: 2026-04-05*
