# Security Audit — Phase 2: Conversations Resource

**Date:** 2026-04-06
**Auditor:** GSD Security Auditor (retroactive analysis)
**ASVS Level:** 1
**Note:** No formal threat model was defined in PLAN.md. This is a retroactive analysis of implemented code.

---

## Threat Register (Retroactive)

| Threat ID | Category | Description | Disposition | Status |
|-----------|----------|-------------|-------------|--------|
| RT-01 | Input Validation | Atom table exhaustion via `String.to_existing_atom` on user-controlled params | mitigate | CLOSED |
| RT-02 | Authorization | No per-user authorization — all authenticated panel users see all conversations | accept | CLOSED |
| RT-03 | Data Exposure | JSON export includes user_id, metadata, tool_calls — may contain sensitive data | accept | CLOSED |
| RT-04 | XSS | User-provided values (titles, tags, content) rendered in HEEx templates | mitigate | CLOSED |
| RT-05 | Denial of Service | `list_conversations_with_stats` loads ALL conversations + O(N) store calls | accept | CLOSED |
| RT-06 | Injection | Conversation IDs passed directly to Store operations without format validation | accept | CLOSED |
| RT-07 | IDOR | Any panel user can view/edit/delete any conversation by manipulating URL ID | accept | CLOSED |
| RT-08 | Input Validation | `per_page` and `page` params parsed from strings — integer overflow or negative values | mitigate | CLOSED |
| RT-09 | Data Exposure | Markdown export includes raw message content — no sanitization needed (raw text output) | mitigate | CLOSED |

---

## Detailed Findings

### RT-01: Atom Table Exhaustion (CLOSED — mitigated)

**Threat:** User-controlled strings converted to atoms could exhaust the BEAM atom table (atoms are never garbage collected).

**Evidence of mitigation:**
- `in_memory_table_live.ex:180` — `String.to_existing_atom(column)` for sort column. Only converts to atoms that already exist in the BEAM. If the atom does not exist, raises `ArgumentError`.
- `in_memory_table_live.ex:204` — Filter keys use `String.to_existing_atom(k)` wrapped in a `rescue ArgumentError` block (lines 208-210). Unknown filter keys are silently ignored.
- `in_memory_table_live.ex:235` — Row actions use `String.to_existing_atom(action)`. Only "view" and "delete" are valid actions (defined at compile time).
- `conversations_live.ex:79` — `String.to_existing_atom(field)` for edit_start. Only `:title` and `:tags` are valid (exist at compile time).
- `deps/phoenix_filament/lib/phoenix_filament/table/params.ex:62-66` — `safe_to_atom/2` wraps `String.to_existing_atom` in rescue, falls back to `:id` default.
- `deps/phoenix_filament/lib/phoenix_filament/table/params.ex:77-81` — `safe_to_existing_atom/1` wraps in rescue, returns nil for unknown atoms.

**Verdict:** All atom conversion uses `String.to_existing_atom` (never `String.to_atom`). The filter handler has an explicit rescue. The Params module has rescue wrappers. Atom exhaustion is not possible.

### RT-02: No Per-User Authorization (CLOSED — accepted risk)

**Threat:** `ConversationsLive` does not filter conversations by the current user. Any authenticated admin panel user can see all conversations from all users.

**Evidence:** `load_conversations/1` calls `StoreAdapter.list_conversations_with_stats(store)` with no user_id filter. `load_conversation/2` loads any conversation by ID without ownership check. `delete_conversation` and `update_conversation` operate on any ID.

**Accepted risk rationale:** This is an **admin panel plugin**. The design context (02-CONTEXT.md) explicitly states "Admin users can browse, inspect, and manage **all** conversations." PhoenixFilament panels are behind authentication. All panel users are expected to be administrators with full access. Per-user access control is not a requirement.

### RT-03: Data Exposure in JSON Export (CLOSED — accepted risk)

**Threat:** `Exporter.to_json/1` includes `user_id`, `metadata`, and `tool_calls` which could contain API keys or internal system information.

**Evidence:** `exporter.ex:18-28` serializes id, title, user_id, tags, model, metadata, timestamps, and messages with tool_calls.

**Accepted risk rationale:** Export is only accessible from the show view, which is behind the admin panel authentication. The metadata and tool_calls fields come from the Store and reflect what was stored during AI conversations. API keys should never be stored in conversation metadata (they belong in provider config). If they are, that is a data hygiene issue in the host application, not a plugin vulnerability.

### RT-04: XSS via User Content (CLOSED — mitigated)

**Threat:** User-provided conversation titles, tags, and message content could contain malicious HTML/JavaScript.

**Evidence of mitigation:**
- HEEx templates use `{}` interpolation syntax (e.g., `{@conversation.title}`, `{tag}`) which auto-escapes HTML by default in Phoenix LiveView. Lines 299, 333, etc. in conversations_live.ex.
- Message content is rendered via `MessageComponent.message/1` which uses MDEx for Markdown-to-HTML conversion. MDEx has built-in XSS sanitization via ammonia (Rust NIF). This is documented in CLAUDE.md technology decisions.
- Export content is delivered as file downloads (JSON and Markdown raw text), not rendered as HTML in the browser.

**Verdict:** Phoenix HEEx auto-escaping and MDEx/ammonia sanitization provide defense-in-depth against XSS.

### RT-05: Denial of Service via Full Data Load (CLOSED — accepted risk)

**Threat:** `list_conversations_with_stats/2` loads ALL conversations from the Store, then issues O(N) `sum_cost` calls. With thousands of conversations, this could cause memory pressure and slow response times.

**Evidence:** `store_adapter.ex:247-258` — loads all conversations, maps over each with `build_stats/3` which calls `compute_total_cost/2` per conversation.

**Accepted risk rationale:** Explicitly documented as a known limitation. The design spec (BRAINSTORM.md section 9) states: "Performance under 1000+ conversations (documented limitation)" is not tested. Decision D-02 in 02-CONTEXT.md acknowledges this: "works well up to ~1000 conversations." The deferred section lists "Server-side pagination in PhoenixAI.Store" as a future improvement. For the admin panel use case, this is acceptable.

### RT-06: Conversation ID Validation (CLOSED — accepted risk)

**Threat:** Conversation IDs from URL params are passed directly to `StoreAdapter.get_conversation_with_stats(store, id)` without format validation.

**Evidence:** `conversations_live.ex:55-56` — `%{"id" => id}` from handle_params is passed to `load_conversation(socket, id)` then to `StoreAdapter.get_conversation_with_stats(store, id)` then to `Store.load_conversation(id, store: store)`.

**Accepted risk rationale:** The ID is used as a lookup key in the Store. If it does not match any conversation, the Store returns `{:error, :not_found}`, which is handled gracefully (conversations_live.ex:489 assigns `nil`, which renders "Conversation not found"). No SQL injection risk because the Store API uses parameterized queries (Ecto backend) or ETS key lookup (ETS backend). The ID is never used in file paths or shell commands.

### RT-07: IDOR — Cross-User Conversation Access (CLOSED — accepted risk)

**Threat:** A user can access, modify, or delete another user's conversation by changing the ID in the URL.

**Evidence:** Same as RT-02. No ownership verification exists.

**Accepted risk rationale:** Same as RT-02. This is an admin panel where all users are administrators. The "User" column in the table explicitly shows conversations from all users. This is by design.

### RT-08: Integer Parsing for Pagination (CLOSED — mitigated)

**Threat:** Malicious `page` or `per_page` URL parameters could cause unexpected behavior (negative pages, extremely large page sizes).

**Evidence of mitigation:**
- `deps/phoenix_filament/lib/phoenix_filament/table/params.ex:26` — `page` is parsed with `parse_int/2` (defaults to 1) then clamped with `max(1)`.
- `params.ex:19-21` — `per_page` is parsed then validated against the allowed `page_sizes` list ([25, 50, 100]). If not in the list, falls back to the default.
- `in_memory_table_live.ex:128-132` — `apply_pagination/3` uses `Enum.slice(offset, per_page)` which safely handles out-of-range values (returns empty list).

### RT-09: Markdown Export Content (CLOSED — mitigated)

**Threat:** Markdown export could contain executable scripts if rendered by a Markdown viewer.

**Evidence of mitigation:** `exporter.ex:78-93` — Message content is interpolated as raw text into the Markdown document. The exported file is plain text (.md). It is not rendered to HTML by the plugin. If a downstream Markdown viewer renders it, that viewer's sanitization applies. The plugin does not control downstream rendering.

---

## Accepted Risks Log

| Threat ID | Risk | Justification |
|-----------|------|---------------|
| RT-02 | All panel users see all conversations | Admin panel — all users are administrators by design |
| RT-03 | JSON export includes metadata/tool_calls | Admin-only access; API keys should not be in conversation metadata |
| RT-05 | Full data load for <1000 conversations | Documented limitation; server-side pagination deferred |
| RT-06 | Conversation IDs not format-validated | Store handles not-found gracefully; no injection vector |
| RT-07 | No ownership check on CRUD operations | Same as RT-02 — admin panel design |

---

## Unregistered Flags

None. No SUMMARY.md with threat flags exists for this phase.

---

*Audit completed: 2026-04-06*
*Phase: 02-conversations-resource*
