# Phase 2: Conversations Resource - Context

**Gathered:** 2026-04-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Admin users can browse, inspect, and manage all conversations through a dedicated resource page backed by the StoreAdapter. Includes paginated table with search/filters, show page with full message thread, edit title/tags, soft/hard delete, and export as JSON/Markdown.

Requirements: CONV-01, CONV-02, CONV-03, CONV-04, CONV-05, CONV-06, CONV-07, CONV-08

</domain>

<decisions>
## Implementation Decisions

### Architecture
- **D-01:** Custom LiveView (`ConversationsLive`), NOT PhoenixFilament.Resource — Resource is tightly coupled to Ecto (QueryBuilder, CRUD, pagination all use Ecto.Query). Since StoreAdapter speaks to PhoenixAI.Store (which can be ETS or Ecto), a custom LiveView avoids the coupling entirely. Pattern follows ChatLive from Phase 1.

### Data Loading & Filtering
- **D-02:** Client-side pagination and filtering — load all conversations from Store, paginate/search/sort in-memory in the LiveView process. The Store API has no pagination or search params. This works well up to ~1000 conversations and is consistent with the current chat sidebar pattern. If scale becomes an issue, Store pagination can be added later without changing the UI.
- **D-03:** Search by title and user_id (text match, case-insensitive). Filter by tags (multi-select), status (active/deleted), and date range. Sort by title, created_at, message_count, total_cost.
- **D-04:** Message count and total cost are computed per-conversation when loading — load conversation, count messages, sum cost records. Cache in assigns to avoid recomputation on re-render.

### Show Page
- **D-05:** Chat-style layout reusing MessageComponent from Phase 1 (user right, assistant left) + metadata sidebar with cost, tokens, tags, timestamps. The show page is read-only — no sending messages. Reuses the same Markdown rendering pipeline.
- **D-06:** Per-message token count displayed inline. Accumulated cost in a footer summary bar.

### Edit & Delete
- **D-07:** Edit title and tags via inline form (not a separate page). Tags as comma-separated input or tag pills.
- **D-08:** Soft-delete with confirmation modal. Hard-delete available only if explicitly enabled in config (admin-level action). Deleted conversations can be filtered in/out via the status filter.

### Export
- **D-09:** Both JSON and Markdown export — separate download buttons on the show page. JSON includes full conversation structure (messages, metadata, costs). Markdown renders a human-readable document with message thread formatted.
- **D-10:** Export happens server-side — generate content, send as file download via `send_download/3`.

### Navigation & Plugin Integration
- **D-11:** Conversations page registered as a route in the plugin's `register/2` — appears in nav under the "AI" group (or configured nav_group). Only visible when `conversations: true` in config.
- **D-12:** Route: `/ai/conversations` (index), `/ai/conversations/:id` (show). Push_patch for navigation between list and detail.

### Claude's Discretion
- Table column widths and responsive behavior
- Exact filter UI layout (sidebar vs top bar)
- Empty state design for conversations list
- Loading states during data fetch
- Date formatting patterns
- Tag badge colors

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Conversations Requirements
- `.planning/REQUIREMENTS.md` — CONV-01 through CONV-08 define the full requirements
- `.planning/ROADMAP.md` §Phase 2 — Success criteria with specific testable assertions

### Existing Code (Phase 1)
- `lib/phoenix_filament_ai/store_adapter.ex` — Current CRUD API, must extend for Phase 2 needs
- `lib/phoenix_filament_ai/chat/chat_page.ex` — LiveView pattern to follow (ChatLive)
- `lib/phoenix_filament_ai/chat/sidebar.ex` — Client-side search/filter pattern
- `lib/phoenix_filament_ai/components/message_component.ex` — Reuse for show page thread rendering
- `lib/phoenix_filament_ai/components/markdown.ex` — Reuse for Markdown rendering

### PhoenixAI.Store API
- `deps/phoenix_ai_store/lib/phoenix_ai/store.ex` — Store API functions: list_conversations, load_conversation, save_conversation, delete_conversation, get_cost_records, sum_cost
- `deps/phoenix_ai_store/lib/phoenix_ai/store/conversation.ex` — Conversation struct: id, user_id, title, tags, model, messages, metadata, deleted_at, inserted_at, updated_at

### PhoenixFilament (reference only — NOT using Resource)
- `deps/phoenix_filament/lib/phoenix_filament/resource.ex` — Resource system reference (Ecto-coupled, NOT suitable for our use case)
- `deps/phoenix_filament/lib/phoenix_filament/table/table_live.ex` — Table component reference for UI patterns

### Plugin API
- `lib/phoenix_filament/ai.ex` — Plugin register/2 where conversations route/nav must be added

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `MessageComponent` — renders user/assistant/system/error messages with Markdown. Reuse directly for show page thread.
- `Markdown` module — render_complete/1 for finalized messages. Reuse for both show page and Markdown export.
- `StoreAdapter` — already has list_conversations, get_conversation, update_conversation, delete_conversation. Extend with computed fields (message_count, total_cost).
- `Sidebar` component — client-side search pattern (case-insensitive text matching). Adapt for table search.
- `ChatLive` pattern — mount -> load data, handle_params for URL routing, handle_event for CRUD. Follow same structure.

### Established Patterns
- Client-side data filtering (chat_page.ex `maybe_filter_by_query/2`)
- `push_patch` for SPA-like navigation without full reload
- `send_download/3` available in LiveView for file downloads
- `Phoenix.LiveView.JS` for confirmation modals (no extra JS)
- Conversation struct has `deleted_at` for soft-delete, `tags` as string array

### Integration Points
- Plugin `register/2` — add conversations route and nav item (conditional on `conversations: true`)
- StoreAdapter — extend with `conversation_with_stats/2` for message_count and total_cost
- Config — `conversations` feature toggle already defined in NimbleOptions schema (default: false)

</code_context>

<specifics>
## Specific Ideas

- Show page should feel like reading a conversation transcript — chat-style layout, not a data dump
- Table should show meaningful stats at a glance (message count, cost) without needing to open each conversation
- Export Markdown should be readable as a standalone document (with headers, participant labels, timestamps)

</specifics>

<deferred>
## Deferred Ideas

- Server-side pagination in PhoenixAI.Store — defer until scale requires it (>1000 conversations)
- Batch operations (bulk delete, bulk export) — potential v0.2+ feature
- Conversation merging or splitting — out of scope
- Real-time updates (new messages appear while viewing) — out of scope for admin CRUD view

</deferred>

---

*Phase: 02-conversations-resource*
*Context gathered: 2026-04-06*
