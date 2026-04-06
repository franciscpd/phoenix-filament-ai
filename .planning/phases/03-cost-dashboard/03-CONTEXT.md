# Phase 3: Cost Dashboard - Context

**Gathered:** 2026-04-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Three dashboard widgets give admin users cost visibility: stats overview with trend sparklines, charts (bar by period + pie by provider/model), and top consumers table. All using Decimal arithmetic, server-side SVG rendering (no JavaScript), and data from PhoenixAI.Store cost records.

Requirements: COST-01, COST-02, COST-03, COST-04, COST-05, COST-06, COST-07

</domain>

<decisions>
## Implementation Decisions

### Layout
- **D-01:** Dedicated page at `/ai/costs` via CostsLive — not dashboard widgets. Route and nav already registered in plugin when `cost_dashboard: true`.
- **D-02:** Vertical layout: stats cards (top row) → charts (middle row: bar left + pie right) → top consumers table (bottom). Overview-to-detail flow.

### Visualization
- **D-03:** Sparklines in stat cards rendered as inline SVG manually (polyline with ~30 data points). No library dependency for sparklines — simple enough to hand-craft.
- **D-04:** Bar chart (spending by day/week/month) and pie chart (distribution by provider/model) rendered via Plox library — server-side SVG with HEEx components. Replaces Contex from original stack recommendation.
- **D-05:** Plox isolated behind a `PhoenixFilamentAI.Charts` module boundary — if library needs replacing, only one module changes.

### Filters and Period
- **D-06:** Global filter bar at page top affects all widgets simultaneously. Filters: period, provider, model, user. Single `handle_event("filter_changed", ...)` updates all assigns.
- **D-07:** Period selection via preset buttons (7d, 30d, 90d, 1y) plus custom date range using native HTML5 date inputs (no JS date picker).
- **D-08:** Sparkline trend period follows the global period filter — no separate toggle per stat card. Consistent with all other widgets reacting to the same filters.

### Data and Store API
- **D-09:** Client-side aggregation — fetch raw cost records via `StoreAdapter` (wrapping `Store.get_cost_records/2`), aggregate in Elixir. Consistent with Phase 2 pattern. No server-side aggregation in Store API.
- **D-10:** Dedicated `PhoenixFilamentAI.CostAggregator` module with pure functions: `by_period/2`, `by_model/2`, `top_consumers/2`, `stats_overview/2`. Receives list of cost records, returns aggregated data. CostsLive orchestrates, CostAggregator computes. Highly testable without Store.
- **D-11:** Decimal arithmetic end-to-end (COST-07). StoreAdapter returns Decimal values. All aggregations use `Decimal.add/2`, `Decimal.div/2`. Float conversion only at SVG render time (Plox coordinates). Typespecs enforce `Decimal.t()` throughout.

### Claude's Discretion
- Stat card visual design (colors, icons, sizing)
- Chart color palette and styling
- Top consumers table column widths and responsive behavior
- Empty state when no cost data exists
- Loading states during data fetch
- Number formatting (currency symbol, decimal places)
- Bar chart granularity mapping (7d→daily, 30d→daily, 90d→weekly, 1y→monthly)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Cost Dashboard Requirements
- `.planning/REQUIREMENTS.md` — COST-01 through COST-07 define the full requirements
- `.planning/ROADMAP.md` §Phase 3 — Success criteria with 4 testable assertions

### Cost Tracking PRD
- `.planning/phoenix_filament_ai_prd.md` §4.3 — Cost tracking dashboard: stats overview, cost chart, top consumers
- `.planning/phoenix_filament_ai_prd.md` §4.3.1 — Cost stats overview widget spec
- `.planning/phoenix_filament_ai_prd.md` §4.3.2 — Cost chart widget spec (bar + pie)
- `.planning/phoenix_filament_ai_prd.md` §4.3.3 — Top consumers table spec

### Existing Code (Phase 1 + Phase 2)
- `lib/phoenix_filament_ai/store_adapter.ex` — StoreAdapter with `sum_cost` and `compute_total_cost` already implemented. Extend with `get_cost_records` and aggregation support.
- `lib/phoenix_filament/ai.ex` — Plugin already registers `/ai/costs` route to `CostsLive` and "Costs" nav item when `cost_dashboard: true`.
- `lib/phoenix_filament_ai/config.ex` — Config has `cost_dashboard: false` toggle already defined.
- `lib/phoenix_filament_ai/conversations/conversations_live.ex` — Custom LiveView pattern to follow (similar layout structure).

### PhoenixAI.Store API
- `deps/phoenix_ai_store/lib/phoenix_ai/store.ex` — Store API: `sum_cost/2`, `get_cost_records/2` for raw cost data

### Chart Library
- Plox on Hex — server-side SVG graphing components for Phoenix/LiveView (verify API before implementation)

### Architecture Research
- `.planning/research/ARCHITECTURE.md` — CostDashboard component architecture and StoreAdapter integration pattern

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `StoreAdapter.compute_total_cost/2` — already wraps `Store.sum_cost/2`, returns Decimal. Extend for filtered aggregation.
- `StoreAdapter.list_conversations_with_stats/2` — pattern for loading + computing stats over Store data. Follow same approach for cost records.
- Plugin registration in `ai.ex` — route `/ai/costs` → `CostsLive` and nav "Costs" already wired when feature enabled.
- Config `cost_dashboard: false` — toggle already in NimbleOptions schema.
- ConversationsLive pattern — mount → load data, handle_params for URL, handle_event for interactions.

### Established Patterns
- Custom LiveView (not Resource) — established in Phase 2, same approach for CostsLive
- Client-side filtering and pagination — from ConversationsLive and ChatLive sidebar
- `send_download/3` — available if cost data export is needed later
- `Phoenix.LiveView.JS` — for interactive UI without custom JS

### Integration Points
- StoreAdapter — new functions: `list_cost_records/2` wrapping `Store.get_cost_records/2`
- CostAggregator — new module for all aggregation logic
- Charts module — new module boundary for Plox integration
- CostsLive — new LiveView at `/ai/costs`

</code_context>

<specifics>
## Specific Ideas

- Charts must be server-side SVG with zero JavaScript — Plox fits this constraint perfectly
- Sparklines should be lightweight inline SVG, not a library call — keeps stat cards fast and simple
- Filter bar should feel like a control panel at the top — presets as buttons (not dropdown), date inputs for custom range
- Contex (originally recommended in stack) replaced by Plox — more actively maintained, native HEEx components

</specifics>

<deferred>
## Deferred Ideas

- Server-side aggregation in PhoenixAI.Store — defer until scale requires it (>10k cost records)
- Cost data export (CSV/JSON download) — potential future enhancement
- Cost alerts/thresholds (notify when spending exceeds X) — out of scope for v1
- Per-request cost breakdown (input vs output tokens) — depends on Store granularity
- Cache layer with ETS for aggregated cost data — premature optimization, revisit if performance issues arise

</deferred>

---

*Phase: 03-cost-dashboard*
*Context gathered: 2026-04-06*
