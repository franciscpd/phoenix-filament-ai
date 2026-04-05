# Feature Landscape

**Domain:** AI admin panel plugin (Elixir/Phoenix/LiveView ecosystem)
**Project:** phoenix_filament_ai
**Researched:** 2026-04-05
**Overall confidence:** MEDIUM — Elixir-native AI admin plugin space has no direct comparators; findings derived from Filament PHP plugin ecosystem (closest analog), LibreChat, Retool AI, and AI chat UI research.

---

## Research Approach

No Elixir/Phoenix-native AI admin panel plugins exist at this level of scope (confirmed by hex.pm search). Research drew from:
- Filament PHP plugin ecosystem (Laravel analog, highest signal)
- LibreChat (open-source, full-featured AI chat platform)
- Retool AI (commercial, admin-panel-adjacent)
- Directus AI (headless CMS AI features)
- AI chat UI best practice research (2025)
- Enterprise AI observability patterns (LangSmith, Lunary, Langfuse)

---

## Table Stakes

Features users expect. Missing = product feels incomplete or they build their own.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Token-by-token streaming | Standard since ChatGPT popularized it. "A response that waits until completion feels broken" (verified by multiple sources). | Medium | `handle_info` pattern already chosen in PRD. Buffering incomplete markdown during stream is the hard part. |
| Markdown rendering in responses | AI outputs markdown by default — code blocks, bold, lists. Without it, responses look like raw text with asterisks. | Low–Medium | Earmark + server-side sanitization chosen. The tricky part is rendering mid-stream without layout thrash. |
| Conversation persistence | Without persistence, every page reload starts fresh — users cannot continue or revisit work. | Medium | Backed by PhoenixAI.Store. Both ETS and Ecto adapters must work. |
| New conversation action | Users need to reset context cleanly. A "new conversation" button is the universal affordance. | Low | Already in PRD (dashboard widget and chat page). |
| Conversation list / history | Ability to see and navigate previous conversations. Every mature AI chat interface (ChatGPT, Claude, Perplexity) shows this in a sidebar. | Medium | Chat page has sidebar; conversations resource provides admin CRUD view. |
| System prompt configuration | Developers need to set context for the AI (role, domain, capabilities). All Filament PHP plugins that support this see it as essential. | Low | Plugin opts already designed for this. |
| Dark mode support | Every reviewed Filament PHP AI plugin lists dark mode. PhoenixFilament admin panels default to dark-capable themes. | Low | PhoenixFilament's theme system handles this automatically. |
| Typing / loading indicator | Users need feedback that the model is working. Without it, a 2-second wait feels like a freeze. | Low | PRD calls out "typing..." indicator component. |
| Auto-scroll to latest message | Standard chat UX expectation. Missing = user manually scrolls on every response. | Low | CSS + LiveView hook required. |
| Basic conversation CRUD | At minimum, list conversations and delete them. An admin tool without delete is considered broken. | Medium | Conversations resource covers full CRUD. |

---

## Differentiators

Features that set phoenix_filament_ai apart. Not universally expected from admin plugins, but create meaningful value and competitive advantage.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Cost tracking dashboard | No reviewed Filament PHP AI plugin includes cost visibility. LibreChat's admin panel cost features are incomplete as of 2025 ("will be in future releases"). Cost blindness is a real pain — developers discover runaway spending only on the provider bill. | High | Depends on PhoenixAI.Store cost recording. Three widgets: stats overview, chart by period/model, top consumers. |
| Event log / audit trail | Compliance and debugging use case. Enterprise AI observability tools (LangSmith, Langfuse) charge for this. Having it built-in as a PhoenixFilament admin view is rare. No reviewed Filament plugin offers this. | Medium | Cursor-based pagination is important here — offset pagination breaks on high-volume event tables. |
| Storage-backend-agnostic (ETS + Ecto) | Most Filament PHP plugins assume Eloquent/SQL directly. Supporting ETS means the plugin works in development/testing without a database migration. | Medium | The store adapter pattern is the differentiator here. |
| Tool call visualization | Rendering tool calls as collapsible cards in conversation show/chat views makes AI behavior inspectable and debuggable — critical for teams building agentic features. LibreChat does this; no Filament PHP plugin does. | Medium | PRD specifies `tool_call_card.ex` component. |
| Per-message token usage display | Shows token count per message in conversation show view. Only LibreChat-class platforms offer this. Useful for debugging prompt engineering. | Low–Medium | Requires PhoenixAI.Store to persist per-message token counts. |
| Conversation export (JSON / Markdown) | Every major AI chat tool (ChatGPT, Claude) now supports export. Tools like ai-chat-exporter exist as browser extensions precisely because platforms don't build it in. Having it native in the admin panel is a strong UX differentiator. | Low | PRD includes this on chat page. Format: JSON (developer) + Markdown (human-readable). |
| Mix task installer | `mix phoenix_filament_ai.install` using Igniter for AST manipulation. No reviewed Filament PHP plugin provides an automated installer of this quality. Reduces time-to-working from 20 minutes to < 5 minutes. | Medium | Validates deps, injects plugin config, generates migrations. |
| Backend-aware ETS detection + warning | If the store uses ETS (volatile backend), showing a dashboard warning prevents silent data loss surprises on restart. Proactive, not reactive. | Low | One-line banner widget check on boot. |
| Full-screen chat page with sidebar | Dashboard widgets are compact by design. A dedicated full-screen page allows longer conversations with navigation history. ChatGPT-style 2-column layout. Only the HuggingFace Chat Filament plugin approaches this — none do it as a proper admin page with resource navigation. | High | Reuses ChatComponent from Phase 1, so marginal cost vs standalone implementation. |

---

## Anti-Features

Features to explicitly NOT build in v0.1.x. Building these would add complexity without proportional value at this stage.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Visual RAG pipeline / document upload | Requires file upload UI, embedding pipeline management, vector DB configuration — a product in itself. No admin panel AI plugin in any ecosystem attempts this. | Document that users should configure RAG at the PhoenixAI layer; the plugin displays results transparently |
| Visual tool builder (create tools via UI) | Tool definitions are code — developer concern. A drag-and-drop tool builder is a full product (cf. Retool's workflow builder, n8n). | Accept tools as Elixir modules configured via `tools: [MyTool]` in plugin opts |
| Visual guardrails policy editor | Policy DSL editors are complex, error-prone, and rarely used after setup. The v0.1 approach of `:default | :strict | :permissive` covers 90% of use cases. | Config-only guardrails via plugin opts; display violations in event log |
| Real-time collaborative chat | Admin panels are single-user authenticated sessions. Multi-user concurrency adds significant complexity (merge conflicts, turn indicators, CRDTs) with no value for target persona. | Document that concurrent access to same conversation is not supported |
| Voice input/output | Adds Web Audio API, browser permission flows, transcription pipeline, and TTS rendering. Out of scope for a developer admin tool. | Not planned |
| Image generation UI | Image gen requires file storage, rendering, download flows — significant scope. Admin panels are not the right surface for generation tools. | Not planned |
| Fine-tuning management | Fine-tuning is a provider-specific workflow (OpenAI, Anthropic have their own UIs). No admin plugin in any ecosystem attempts to wrap this. | Link to provider dashboards from cost tracking |
| Prompt marketplace / library | Community feature requiring server infrastructure, moderation, discoverability. Solo maintainer constraint makes this unviable. | Users can configure system prompts via plugin opts |
| OAuth / SSO | PhoenixFilament provides its own auth. Adding OAuth means owning a parallel auth flow. Not needed for admin panel use case. | Use PhoenixFilament's existing auth |
| Feedback collection (thumbs up/down) | Valuable for model training pipelines, but requires feedback storage, reporting, and pipeline integration. Adds complexity without immediate value. | Can be added in v0.2 if demand emerges |
| Stop generation button | Highly requested in AI chat UX research. However: PhoenixAI uses Finch SSE streaming, and aborting an in-flight HTTP stream requires explicit cancellation support from PhoenixAI. Defer until PhoenixAI exposes a cancellation API. | Document as known limitation; PhoenixAI.Store.converse/3 should complete naturally |
| Message branching / alternate responses | Conversation tree management (ChatGPT-style "try again" branching) adds significant data model complexity to PhoenixAI.Store. | Provide a simpler "copy and start new conversation" workaround |

---

## Feature Dependencies

```
Plugin Registration (register/2 + boot/1)
    └── NimbleOptions Config Validation
            └── Chat Component (reusable)
                    ├── Dashboard Chat Widget
                    │       └── PhoenixAI.Store.converse/3 integration
                    └── Chat Page (full-screen)
                            └── Conversation Sidebar
                                    └── Store Adapter

Store Adapter (CRUD → PhoenixAI.Store API)
    └── Conversations Resource
            ├── Conversation List (index)
            ├── Conversation Show (thread view)
            │       └── Tool Call Card Component
            │       └── Per-message Token Display
            └── Conversation Edit/Delete

PhoenixAI.Store Cost Recording (provider dependency)
    └── Cost Tracking Widgets
            ├── Stats Overview Widget
            ├── Cost Chart Widget
            └── Top Consumers Table Widget

PhoenixAI.Store Event Log (provider dependency)
    └── Event Log Viewer
            └── Cursor-based Pagination

Conversations Resource (see above)
    └── Conversation Export (JSON/Markdown)
            (depends on Show page data being accessible)
```

**Critical path:** Plugin registration → Config validation → Chat Component → Store integration. Everything else branches from these.

**ETS/Ecto split:** Store adapter is the isolation point. Cost tracking and event log depend on PhoenixAI.Store exposing `sum_cost/2`, `get_cost_records/2`, `list_events/2`, `count_events/2`. If these APIs are not stable, those features need to be flagged for phase-specific research.

---

## MVP Recommendation

Prioritize:

1. Plugin registration + config validation — nothing works without this
2. Chat component (streaming, markdown, typing indicator, auto-scroll) — the core value
3. Dashboard chat widget — first visible deliverable; validates the full stack
4. Conversations resource — table stakes for admin panel utility
5. Chat page — high value, leverages chat component already built

Defer (post v0.1.0-rc.1):
- Cost tracking dashboard — high value, but no dependencies block later phases
- Event log viewer — useful for compliance; not blocking
- Mix task installer — developer convenience, not functional requirement; build last

This ordering matches the PRD phases exactly, which is good signal the PRD's phase structure is sound.

---

## Competitive Gap Analysis

Based on research of all reviewed Filament PHP AI plugins:

| Capability | ChatGPT Bot (icetalker) | OpenAI Assistant (Ercogx) | ChatGPT Agent (bas-schleijpen) | Assistant Engine (edeoliv) | phoenix_filament_ai |
|------------|------------------------|--------------------------|-------------------------------|---------------------------|---------------------|
| Streaming | No | Unknown | No | No | Yes |
| Conversation persistence | No | Yes (OpenAI threads) | Unknown | Yes | Yes (multi-backend) |
| Conversation list | No | Yes | No | Partial | Yes |
| Markdown rendering | Unknown | Unknown | Unknown | Unknown | Yes |
| Cost tracking | No | No | No | No | Yes |
| Audit/event log | No | No | No | No | Yes |
| Tool call visualization | No | No | No | Partial (tool calls executed, not displayed) | Yes |
| Multi-provider | No | No | No | No | Yes (via PhoenixAI) |
| Backend-agnostic storage | No | No (OpenAI threads) | No | No | Yes (ETS + Ecto) |
| Installer | No | No | No | No | Yes |
| Export | No | No | No | No | Yes |

Confidence: MEDIUM (plugin documentation is sparse; "No" means "not documented", not confirmed absent)

---

## Sources

- [Filament PHP OpenAI Assistant Plugin](https://filamentphp.com/plugins/ercogx-openai-assistant) — feature comparison reference
- [Filament PHP ChatGPT Bot (icetalker)](https://github.com/icetalker/filament-chatgpt-bot) — minimal plugin as baseline
- [Filament PHP Assistant Engine (edeoliv)](https://github.com/edeoliv/filament-assistant) — context-aware plugin comparison
- [Filament PHP ChatGPT Agent (bas-schleijpen)](https://filamentphp.com/plugins/bas-schleijpen-chatgpt-agent) — feature set review
- [filament-model-ai (postare)](https://github.com/postare/filament-model-ai) — model-context pattern
- [LibreChat Token Usage Documentation](https://www.librechat.ai/docs/configuration/token_usage) — cost tracking patterns
- [LibreChat 2025 Roadmap](https://www.librechat.ai/blog/2025-02-20_2025_roadmap) — admin panel gaps confirmed
- [AI Chat UI Best Practices (DEV Community)](https://dev.to/greedy_reader/ai-chat-ui-best-practices-designing-better-llm-interfaces-18jj) — table stakes definition, streaming UX
- [Comparing Conversational AI Tool UIs 2025](https://intuitionlabs.ai/articles/conversational-ai-ui-comparison-2025) — sidebar/conversation list patterns
- [Retool AI Features 2025](https://retoolers.io/blog-posts/retool-2025-feature-releases-ai-multipage-apps-agents-more) — enterprise admin AI patterns
- [Directus AI v11.13](https://directus.io/blog/directus-v11-13-release) — MCP/audit trail patterns in CMS admin
- [Top AI Cost Tracking Solutions (Flexprice)](https://flexprice.io/blog/top-5-real-time-ai-usage-tracking-and-cost-metering-solutions-for-startups) — cost dashboard feature expectations
- [Mission Control AI Dashboard](https://mc.builderz.dev) — tool call visualization as differentiator
- [AI Chat Exporter Landscape 2025](https://github.com/TheBluCoder/AI-chat-exporter) — export as emerging standard
