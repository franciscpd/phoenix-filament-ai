# Requirements: phoenix_filament_ai

**Defined:** 2026-04-05
**Core Value:** From a configured `phoenix_ai_store` to a complete AI admin interface in minutes — chat, conversations, cost visibility, and audit trail — all declarative and extensible via PhoenixFilament's plugin API.

## v1 Requirements

### Plugin Foundation

- [ ] **PLUG-01**: Plugin module implements PhoenixFilament.Plugin behaviour with `register/2` and `boot/1`
- [ ] **PLUG-02**: All plugin options validated via NimbleOptions schema with clear error messages
- [ ] **PLUG-03**: Plugin registers navigation items, routes, widgets, and hooks based on feature toggles
- [ ] **PLUG-04**: Plugin boot injects `:ai_store` and `:ai_config` into socket assigns
- [ ] **PLUG-05**: Plugin works with zero configuration beyond `:store`, `:provider`, and `:model`

### Chat

- [ ] **CHAT-01**: Dashboard chat widget renders in the PhoenixFilament dashboard grid with configurable `column_span` and `sort`
- [ ] **CHAT-02**: User can send messages and receive AI responses with token-by-token streaming
- [ ] **CHAT-03**: Streaming uses non-blocking `start_async/3` pattern — LiveView remains responsive during AI response
- [ ] **CHAT-04**: AI responses render Markdown via MDEx with HTML sanitization
- [ ] **CHAT-05**: User can start a new conversation from the widget
- [ ] **CHAT-06**: Conversation persists across page navigations via PhoenixAI.Store
- [ ] **CHAT-07**: "Typing..." indicator displays during streaming
- [ ] **CHAT-08**: Chat auto-scrolls to latest message
- [ ] **CHAT-09**: Submit via Enter, Shift+Enter for new line
- [ ] **CHAT-10**: Full-screen chat page with 2-column layout (sidebar + chat area)
- [ ] **CHAT-11**: Sidebar shows conversation list with search by title and filter by tags
- [ ] **CHAT-12**: User can create, delete, and rename conversations from the chat page
- [ ] **CHAT-13**: User can navigate between conversations without full page reload
- [ ] **CHAT-14**: Tool calls display in collapsible cards with input/output
- [ ] **CHAT-15**: System messages render in a highlighted banner
- [ ] **CHAT-16**: Reusable ChatComponent shared between widget and full-screen page

### Conversations

- [ ] **CONV-01**: Conversations resource shows paginated table with all conversations
- [ ] **CONV-02**: Table columns: title, user, message count, total cost, tags (badges), status (badge), created at — all sortable where applicable
- [ ] **CONV-03**: Table supports search by title and user, filter by user/tags/status/date range
- [ ] **CONV-04**: Show page displays chat-style message thread (user right, assistant left)
- [ ] **CONV-05**: Show page displays per-message token usage and accumulated cost in footer
- [ ] **CONV-06**: User can edit conversation title and tags
- [ ] **CONV-07**: User can soft-delete conversations, admin can hard-delete
- [ ] **CONV-08**: User can export conversation as JSON or Markdown
- [ ] **CONV-09**: Store adapter translates all CRUD operations to PhoenixAI.Store API (no direct Ecto)
- [ ] **CONV-10**: Store adapter works with both ETS and Ecto backends

### Cost Tracking

- [ ] **COST-01**: Stats overview widget shows: total spent, avg cost per conversation, total tokens, number of AI calls — for selectable period
- [ ] **COST-02**: Each stat card shows trend sparkline for last 7/30 days
- [ ] **COST-03**: Cost chart widget shows bar chart (spending by day/week/month) using Contex SVG
- [ ] **COST-04**: Cost chart widget shows pie chart (distribution by provider/model) using Contex SVG
- [ ] **COST-05**: Charts support filters: period, provider, model, user
- [ ] **COST-06**: Top consumers table shows top N users/conversations by spending with columns: user, conversation count, total cost, avg cost, last activity
- [ ] **COST-07**: All cost calculations use Decimal arithmetic (not float)

### Event Log

- [ ] **EVNT-01**: Event log page shows cursor-based paginated table with all events
- [ ] **EVNT-02**: Events filterable by event type, user, conversation, period
- [ ] **EVNT-03**: Detail view shows expanded event JSON
- [ ] **EVNT-04**: Event types display with colored badges (info/default/warning/error per type)

### Installer

- [ ] **INST-01**: `mix phoenix_filament_ai.install` verifies dependencies are installed
- [ ] **INST-02**: Installer adds plugin declaration to existing panel using Igniter AST manipulation
- [ ] **INST-03**: Installer generates migration if using Ecto adapter
- [ ] **INST-04**: Installer updates config with defaults and prints post-installation instructions

## v2 Requirements

### Chat Enhancements

- **CHAT-V2-01**: Stop generation button (requires PhoenixAI cancellation API)
- **CHAT-V2-02**: Message editing and regeneration
- **CHAT-V2-03**: Voice input/output

### Guardrails Management

- **GUAR-01**: Visual guardrails configuration (policy editor UI)
- **GUAR-02**: Visual guardrail violation display in chat

### Advanced Features

- **ADV-01**: Visual RAG pipeline with document upload UI
- **ADV-02**: Multi-tenant cost isolation
- **ADV-03**: Visual tool builder (creating tools via UI)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Image generation | Not core to admin AI assistant use case |
| Fine-tuning management | Out of scope for plugin layer — belongs in PhoenixAI |
| Prompt marketplace | Community feature, premature for v0.1.x |
| Mobile app | Web-first admin panel, mobile not applicable |
| Real-time collaborative chat | Single-user admin sessions |
| OAuth login | PhoenixFilament handles auth independently |
| Direct Ecto queries | Breaks store backend abstraction — use Store API only |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| PLUG-01 | — | Pending |
| PLUG-02 | — | Pending |
| PLUG-03 | — | Pending |
| PLUG-04 | — | Pending |
| PLUG-05 | — | Pending |
| CHAT-01 | — | Pending |
| CHAT-02 | — | Pending |
| CHAT-03 | — | Pending |
| CHAT-04 | — | Pending |
| CHAT-05 | — | Pending |
| CHAT-06 | — | Pending |
| CHAT-07 | — | Pending |
| CHAT-08 | — | Pending |
| CHAT-09 | — | Pending |
| CHAT-10 | — | Pending |
| CHAT-11 | — | Pending |
| CHAT-12 | — | Pending |
| CHAT-13 | — | Pending |
| CHAT-14 | — | Pending |
| CHAT-15 | — | Pending |
| CHAT-16 | — | Pending |
| CONV-01 | — | Pending |
| CONV-02 | — | Pending |
| CONV-03 | — | Pending |
| CONV-04 | — | Pending |
| CONV-05 | — | Pending |
| CONV-06 | — | Pending |
| CONV-07 | — | Pending |
| CONV-08 | — | Pending |
| CONV-09 | — | Pending |
| CONV-10 | — | Pending |
| COST-01 | — | Pending |
| COST-02 | — | Pending |
| COST-03 | — | Pending |
| COST-04 | — | Pending |
| COST-05 | — | Pending |
| COST-06 | — | Pending |
| COST-07 | — | Pending |
| EVNT-01 | — | Pending |
| EVNT-02 | — | Pending |
| EVNT-03 | — | Pending |
| EVNT-04 | — | Pending |
| INST-01 | — | Pending |
| INST-02 | — | Pending |
| INST-03 | — | Pending |
| INST-04 | — | Pending |

**Coverage:**
- v1 requirements: 45 total
- Mapped to phases: 0
- Unmapped: 45 ⚠️

---
*Requirements defined: 2026-04-05*
*Last updated: 2026-04-05 after initial definition*
