# Roadmap: phoenix_filament_ai

## Overview

Five phases take this plugin from a bare Elixir project to a published Hex package. Phase 1 is the critical path: plugin boot, streaming architecture, and the shared ChatComponent must be correct from the start because every later phase builds on them. Phase 2 surfaces the conversation data through a full CRUD resource. Phases 3 and 4 add cost visibility and an audit trail. Phase 5 wraps everything with a developer-friendly installer and ships to Hex.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Foundation + Chat** - Plugin boots, chat widget and full-screen chat page work with streaming, markdown, and conversation persistence
- [ ] **Phase 2: Conversations Resource** - Admin CRUD view for all conversations with search, filters, show thread, export, and soft-delete
- [ ] **Phase 3: Cost Dashboard** - Three dashboard widgets give cost visibility: stats overview, charts by period/model, and top consumers table
- [ ] **Phase 4: Event Log** - Read-only paginated event viewer with filters, type badges, and JSON detail view
- [ ] **Phase 5: Installer + Polish** - Mix task installer, ExDoc documentation, and Hex package release

## Phase Details

### Phase 1: Foundation + Chat
**Goal**: A developer can add the plugin to a PhoenixFilament panel and get a working dashboard chat widget and full-screen chat page with streaming AI responses, markdown rendering, and persistent conversations
**Depends on**: Nothing (first phase)
**Requirements**: PLUG-01, PLUG-02, PLUG-03, PLUG-04, PLUG-05, CHAT-01, CHAT-02, CHAT-03, CHAT-04, CHAT-05, CHAT-06, CHAT-07, CHAT-08, CHAT-09, CHAT-10, CHAT-11, CHAT-12, CHAT-13, CHAT-14, CHAT-15, CHAT-16, CONV-09, CONV-10
**Success Criteria** (what must be TRUE):
  1. Developer adds the plugin with only `:store`, `:provider`, and `:model` options — the panel shows navigation, routes, and widgets with no further configuration
  2. User sends a message in the dashboard chat widget and sees a token-by-token streaming response; the UI remains interactive (input enabled) during streaming
  3. AI responses containing Markdown (headers, code blocks, bold, lists) render as formatted HTML — not raw asterisks
  4. User opens the full-screen chat page, sees a 2-column layout with conversation sidebar and chat area, can create a new conversation, switch between conversations without a full page reload, and rename or delete conversations
  5. Tool call results appear in collapsible cards; system messages render in a highlighted banner; conversation state survives page navigation
**Plans**: TBD
**UI hint**: yes

### Phase 2: Conversations Resource
**Goal**: Admin users can browse, inspect, and manage all conversations through a dedicated resource page backed by the StoreAdapter
**Depends on**: Phase 1
**Requirements**: CONV-01, CONV-02, CONV-03, CONV-04, CONV-05, CONV-06, CONV-07, CONV-08
**Success Criteria** (what must be TRUE):
  1. Conversations index page shows a paginated table with title, user, message count, total cost, tags (badges), status (badge), and created-at columns — all sortable where applicable
  2. User can search conversations by title and user, and filter by user, tags, status, and date range
  3. Conversation show page displays the full message thread (user messages right, assistant messages left) with per-message token usage and accumulated cost in the footer
  4. User can edit conversation title and tags; soft-delete a conversation; admin can hard-delete; user can export a conversation as JSON or Markdown
**Plans**: TBD
**UI hint**: yes

### Phase 3: Cost Dashboard
**Goal**: Admin users can see how much the AI integration is costing, broken down by period, provider, model, and top consumers — all using Decimal arithmetic
**Depends on**: Phase 2
**Requirements**: COST-01, COST-02, COST-03, COST-04, COST-05, COST-06, COST-07
**Success Criteria** (what must be TRUE):
  1. Dashboard shows a stats overview widget with total spent, average cost per conversation, total tokens, and number of AI calls for a user-selected period; each stat card includes a trend sparkline for the last 7 or 30 days
  2. Dashboard shows a bar chart (spending by day/week/month) and a pie chart (distribution by provider/model), both rendered as server-side SVG with no JavaScript — and both respond to period, provider, model, and user filters
  3. Top consumers table lists the top N users/conversations by spending with columns: user, conversation count, total cost, average cost, and last activity
  4. All cost values throughout the UI are computed with Decimal arithmetic — float drift is not possible
**Plans**: TBD
**UI hint**: yes

### Phase 4: Event Log
**Goal**: Admin users can audit all AI events through a paginated, filterable read-only log with detail inspection
**Depends on**: Phase 3
**Requirements**: EVNT-01, EVNT-02, EVNT-03, EVNT-04
**Success Criteria** (what must be TRUE):
  1. Event log page loads with cursor-based pagination (no offset queries) and shows all events in reverse chronological order
  2. User can filter events by event type, user, conversation, and time period; event type column shows colored badges (info/default/warning/error) matching the event's severity
  3. Clicking an event opens a detail view showing the full expanded event JSON
**Plans**: TBD

### Phase 5: Installer + Polish
**Goal**: A developer can install the plugin into a new project in under five minutes using a mix task, and the package is published and documented on Hex
**Depends on**: Phase 4
**Requirements**: INST-01, INST-02, INST-03, INST-04
**Success Criteria** (what must be TRUE):
  1. Running `mix phoenix_filament_ai.install` in a Phoenix project verifies that `phoenix_filament`, `phoenix_ai`, and `phoenix_ai_store` are present; if missing, it prints clear instructions and exits
  2. The installer adds the plugin declaration to the existing panel config using AST manipulation (Igniter) — no manual copy-paste required
  3. When the Ecto backend is detected, the installer generates the migration automatically
  4. After install, the task prints clear post-installation instructions; running `mix hex.publish` succeeds and the package appears on Hex with full ExDoc documentation
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation + Chat | 0/? | Not started | - |
| 2. Conversations Resource | 0/? | Not started | - |
| 3. Cost Dashboard | 0/? | Not started | - |
| 4. Event Log | 0/? | Not started | - |
| 5. Installer + Polish | 0/? | Not started | - |
