# phoenix_filament_ai

## What This Is

`phoenix_filament_ai` is a Hex package that works as a PhoenixFilament plugin, adding AI capabilities to admin panels. It connects PhoenixFilament (declarative UI) with PhoenixAI (AI runtime) and PhoenixAI.Store (conversation persistence), enabling developers to go from a configured store to a complete AI interface — chat with streaming, conversation history, cost dashboard, and event log — with a single plugin declaration.

## Core Value

From a configured `phoenix_ai_store` to a complete AI admin interface in minutes — chat, conversations, cost visibility, and audit trail — all declarative and extensible via PhoenixFilament's plugin API.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Plugin module with `register/2` and `boot/1` via PhoenixFilament.Plugin behaviour
- [ ] Config validation with NimbleOptions for all plugin opts
- [ ] Dashboard chat widget with streaming, markdown rendering, and conversation persistence
- [ ] Full-screen chat page with conversation sidebar, search, and filters
- [ ] Reusable chat component shared between widget and page
- [ ] Conversations resource (list, show, edit, delete) via Store adapter
- [ ] Store adapter translating CRUD to PhoenixAI.Store API (backend-agnostic)
- [ ] Cost tracking dashboard widgets (stats overview, charts, top consumers)
- [ ] Event log viewer with cursor-based pagination and filters
- [ ] Mix task installer (`mix phoenix_filament_ai.install`)
- [ ] Markdown rendering server-side with Earmark + HTML sanitization
- [ ] Streaming via `handle_info` pattern (not LiveView Streams)
- [ ] No direct Ecto dependency — all data through PhoenixAI.Store API

### Out of Scope

- Visual RAG pipeline — requires document upload UI, too complex for v0.1.x
- Multi-tenant cost isolation — future, when PhoenixFilament supports multi-tenancy
- Visual tool builder — creating tools via UI deferred to future
- Visual guardrails configuration — requires policy editor UI (v0.2+)
- Voice input/output — not in scope for admin panel use case
- Image generation — not core to admin AI assistant
- Fine-tuning management — out of scope for plugin layer
- Prompt marketplace — community feature, not v1
- OAuth login — email/password sufficient for PhoenixFilament auth
- Real-time collaborative chat — single-user admin sessions

## Context

- **Ecosystem:** Part of the Phoenix* family — `phoenix_filament` (UI), `phoenix_ai` (runtime), `phoenix_ai_store` (persistence). All published on Hex.
- **Plugin API:** Uses PhoenixFilament's plugin system (`register/2` for nav/routes/widgets, `boot/1` for socket assigns). API is v0.1.x — experimental but stable enough to build against.
- **Store abstraction:** PhoenixAI.Store supports ETS and Ecto backends. The plugin must work with both — no direct Ecto dependency.
- **Streaming pattern:** PhoenixAI uses Finch SSE for AI provider streaming. The recommended pattern is `send(self(), {:ai_chunk, chunk})` + `handle_info` for LiveView integration.
- **Widget system:** PhoenixFilament has 4 widget types. Chat widget uses `Widget.Custom` for native dashboard grid integration.
- **Solo developer:** Single maintainer, open-source from day one.
- **Validation:** Testing against a parallel Phoenix application to validate integration.

## Constraints

- **Tech stack**: Elixir/Phoenix/LiveView — must follow OTP conventions and Phoenix patterns
- **Dependencies**: Only `phoenix_filament`, `phoenix_ai`, `phoenix_ai_store` as runtime deps. Dev deps: `ex_doc`, `credo`, `dialyxir`
- **No JS frameworks**: Zero additional JavaScript frameworks — LiveView + HEEx only
- **Backend-agnostic**: Must work with both ETS and Ecto store backends
- **Plugin API contract**: Must implement PhoenixFilament.Plugin behaviour exactly
- **Markdown rendering**: Server-side with Earmark, no client-side JS renderers

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Streaming via handle_info, not LiveView Streams | AI streaming is token-by-token (hundreds of chunks); Streams is for discrete list items | — Pending |
| Store adapter layer instead of direct Ecto | PhoenixAI.Store supports ETS and Ecto; direct Ecto breaks abstraction | — Pending |
| Widget.Custom for chat widget | Native PhoenixFilament dashboard grid integration (sort, column_span, error handling) | — Pending |
| Server-side Markdown with Earmark | Avoids JS dependencies; LiveView 1.1 HEEx can render safe HTML via raw/1 | — Pending |
| No direct Ecto dependency | Keeps plugin storage-backend agnostic | — Pending |
| Chat widget + chat page in same phase | Both share ChatComponent; delivering together reduces integration overhead | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-05 after initialization*
