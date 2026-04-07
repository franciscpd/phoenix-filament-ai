# Phase 3: Cost Dashboard — Design Spec

**Date:** 2026-04-06
**Status:** Approved
**Approach:** Hybrid — Single Load + Function Components

## Overview

Dedicated cost dashboard page at `/ai/costs` giving admin users visibility into AI spending. Three widget sections — stats overview with sparklines, charts (bar + pie), and top consumers table — all powered by `PhoenixAI.Store` v0.3.0's `list_cost_records/2` API with Decimal arithmetic end-to-end.

## Architecture

### Approach: Hybrid (Single Load + Function Components)

CostsLive loads all cost records once via StoreAdapter, CostAggregator pre-computes all views into separate assign keys. Widgets are function components. LiveView change tracking ensures only affected widgets re-render on filter changes.

**Why this approach:**
- One data load per filter change (simple, consistent with ConversationsLive)
- Separate assigns per widget enable LiveView's built-in change tracking
- Function components are stateless and easy to test
- CostAggregator is a pure module — fully testable without Store

**Rejected alternatives:**
- Single LiveView + flat assigns — re-renders everything on any change
- LiveComponents per widget — unnecessary complexity, multiple Store calls

### Module Structure

```
lib/phoenix_filament_ai/
├── costs/
│   ├── costs_live.ex          # LiveView — mount, load, filter events
│   ├── cost_aggregator.ex     # Pure functions — all aggregation logic
│   └── charts.ex              # Plox wrapper — bar_chart_svg/2, pie_chart_svg/2
├── components/
│   ├── stat_card.ex           # Function component — single stat with sparkline
│   ├── cost_charts.ex         # Function component — bar + pie side by side
│   └── cost_table.ex          # Function component — top consumers table
└── store_adapter.ex           # Extend with list_cost_records/2, count_cost_records/2
```

### Module Responsibilities

**CostsLive** — Orchestrator LiveView.
- Mounts with default filters (`period: :last_7d`)
- `handle_params/3` parses URL into filter assigns, triggers data load
- `handle_event("filter_changed", ...)` updates filters, reloads data
- Calls `load_and_aggregate/1` which does one Store call + one CostAggregator call
- Assigns: `:stats`, `:sparkline_data`, `:bar_chart_data`, `:pie_chart_data`, `:top_consumers`, `:filters`

**CostAggregator** — Pure computation module (no side-effects, no Store access).
- Receives `[CostRecord.t()]`, returns structured map with all widget data
- All arithmetic uses `Decimal` — no floats until SVG render
- Functions are individually testable

**Charts** — Plox integration boundary.
- `bar_chart_svg/2` — spending by period as SVG via Plox
- `pie_chart_svg/2` — distribution by model as SVG via Plox
- If Plox needs replacement, only this module changes
- Sparklines are NOT in this module — they're inline SVG in StatCard component (too simple for a library)

**StoreAdapter** (extensions) — Delegates to Store v0.3.0.
- `list_cost_records/2` → `Store.list_cost_records/2`
- `count_cost_records/2` → `Store.count_cost_records/2`

## Page Layout

### Filter Bar (top of page)

Global filter bar affecting all widgets simultaneously.

- **Period presets:** Buttons — 7d, 30d, 90d, 1y (active state highlighted)
- **Custom range:** Two native HTML5 `<input type="date">` fields
- **Dropdowns:** Provider (All / OpenAI / Anthropic / ...), Model (All / gpt-4o / claude-3.5 / ...), User (All / user list)
- Filter changes trigger `handle_event("filter_changed")` → reload all data

### Stats Cards (4-column grid)

| Card | Value | Sparkline | Trend |
|------|-------|-----------|-------|
| Total Spent | `$142.87` | 7-point SVG polyline (blue) | `↑ 12% vs prev period` |
| Avg / Conversation | `$0.47` | 7-point SVG polyline (amber) | `↓ 3% vs prev period` |
| Total Tokens | `1.2M` | 7-point SVG polyline (purple) | `↑ 8% vs prev period` |
| AI Calls | `304` | 7-point SVG polyline (cyan) | `↑ 15% vs prev period` |

- Sparklines are inline SVG `<polyline>` — no library dependency
- Sparkline period follows global filter (7d filter = 7 data points, 30d = 30 points)
- Trend compares current period to previous equivalent period (e.g., 7d selected → compare this week vs last week; custom range Mar 1-15 → compare Feb 14-28)

### Charts Row (60/40 split)

**Bar Chart (left, 60% width):**
- Spending by day/week/month (granularity auto-mapped from period)
- Granularity mapping: 7d → daily, 30d → daily, 90d → weekly, 1y → monthly
- Rendered via Plox server-side SVG
- X-axis: date labels, Y-axis: dollar amounts

**Pie Chart (right, 40% width):**
- Distribution by provider/model
- Rendered via Plox server-side SVG
- Legend with color swatches + percentages

### Top Consumers Table (full width)

| # | User | Conversations | Total Cost | Avg Cost | Last Activity |
|---|------|---------------|------------|----------|---------------|

- Sorted by total cost descending
- Default top 10, configurable via CostAggregator
- Relative time for last activity ("2 hours ago")

## Data Flow

### CostsLive Lifecycle

```
mount/3
  → assign defaults (filters: %{period: :last_7d})
  → assign page_title: "Costs"

handle_params/3
  → parse URL params into filter assigns
  → load_and_aggregate(socket)

handle_event("filter_changed", params)
  → update filter assigns
  → load_and_aggregate(socket)
```

### load_and_aggregate/1

```elixir
defp load_and_aggregate(socket) do
  store = socket.assigns.store
  filters = build_store_filters(socket.assigns.filters)

  {:ok, %{records: records}} = StoreAdapter.list_cost_records(store, filters)

  aggregated = CostAggregator.compute_all(records, socket.assigns.filters)

  socket
  |> assign(:stats, aggregated.stats)
  |> assign(:sparkline_data, aggregated.sparklines)
  |> assign(:bar_chart_data, aggregated.bar_chart)
  |> assign(:pie_chart_data, aggregated.pie_chart)
  |> assign(:top_consumers, aggregated.top_consumers)
end
```

### CostAggregator API

```elixir
@spec compute_all([CostRecord.t()], map()) :: %{
  stats: %{
    total_spent: Decimal.t(),
    avg_per_conversation: Decimal.t(),
    total_tokens: non_neg_integer(),
    ai_calls: non_neg_integer()
  },
  sparklines: %{
    total_spent: [Decimal.t()],
    avg_cost: [Decimal.t()],
    tokens: [non_neg_integer()],
    calls: [non_neg_integer()]
  },
  bar_chart: [%{date: Date.t(), amount: Decimal.t()}],
  pie_chart: [%{label: String.t(), amount: Decimal.t(), percentage: float()}],
  top_consumers: [%{
    user_id: String.t(),
    conversations: non_neg_integer(),
    total_cost: Decimal.t(),
    avg_cost: Decimal.t(),
    last_activity: DateTime.t()
  }]
}

# Individual functions (also public for unit testing)
@spec stats_overview([CostRecord.t()]) :: stats_map()
@spec sparkline_points([CostRecord.t()], atom()) :: sparkline_map()
@spec spending_by_period([CostRecord.t()], atom()) :: [bar_point()]
@spec distribution_by_model([CostRecord.t()]) :: [pie_slice()]
@spec top_consumers([CostRecord.t()], non_neg_integer()) :: [consumer()]
```

### Granularity Mapping

| Period | Granularity | Sparkline Points |
|--------|-------------|------------------|
| 7d | Daily | 7 |
| 30d | Daily | 30 |
| 90d | Weekly | ~13 |
| 1y | Monthly | 12 |

### StoreAdapter Extensions

```elixir
@spec list_cost_records(atom(), keyword()) ::
        {:ok, %{records: [CostRecord.t()], next_cursor: String.t() | nil}} | {:error, term()}
def list_cost_records(store, filters \\ [])

@spec count_cost_records(atom(), keyword()) ::
        {:ok, non_neg_integer()} | {:error, term()}
def count_cost_records(store, filters \\ [])
```

Delegates to `PhoenixAI.Store` v0.3.0 which supports filters: `:conversation_id`, `:user_id`, `:provider`, `:model`, `:after`, `:before`, `:cursor`, `:limit`.

## Decimal Arithmetic (COST-07)

- StoreAdapter returns `Decimal.t()` for all cost fields
- CostAggregator uses `Decimal.add/2`, `Decimal.div/2`, `Decimal.mult/2` throughout
- Float conversion happens ONLY at SVG render time (Plox chart coordinates)
- Typespecs enforce `Decimal.t()` on all cost-related parameters and return values
- Pie chart `percentage` is the only float — computed at render time for display

## Dependencies

### New Runtime Dependency

- `plox` — server-side SVG graphing components for Phoenix/LiveView. Verify exact version on Hex before adding to mix.exs. Isolated behind `Charts` module boundary.

### Updated Dependency

- `phoenix_ai_store` ~> 0.3.0 — now provides `list_cost_records/2` and `count_cost_records/2` with full filter support

## Plugin Integration

Already wired in Phase 1:
- Route: `/ai/costs` → `PhoenixFilamentAI.CostsLive` (when `cost_dashboard: true`)
- Nav: "Costs" under configured nav_group (when `cost_dashboard: true`)
- Config: `cost_dashboard: false` default in NimbleOptions schema

No changes needed to `ai.ex` or `config.ex`.

## Empty State

When no cost records exist for the selected filters:
- Stats cards show `$0.00` / `0` with flat sparklines
- Charts show "No data for selected period" centered message
- Table shows "No cost records found" empty row

## Error Handling

- Store call failure → flash error + retain previous data in assigns
- Plox render failure → fallback to text-only display (no SVG)
- Invalid filter params → reset to defaults silently

---

*Phase: 03-cost-dashboard*
*Design approved: 2026-04-06*
