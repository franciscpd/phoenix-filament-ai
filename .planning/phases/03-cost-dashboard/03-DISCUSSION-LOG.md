# Phase 3: Cost Dashboard - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-06
**Phase:** 03-cost-dashboard
**Areas discussed:** Layout dos widgets, Visualização de dados, Filtros e período, Dados e Store API

---

## Layout dos widgets

| Option | Description | Selected |
|--------|-------------|----------|
| Página dedicada | CostsLive em /ai/costs com layout próprio. Stats cards no topo, gráficos no meio, tabela embaixo. | ✓ |
| Widgets no dashboard | Stats e chart como Widget.Custom no dashboard grid. Limita espaço e filtros. | |
| Ambos | Widget resumido no dashboard + página completa. Mais trabalho. | |

**User's choice:** Página dedicada
**Notes:** Route already registered in plugin. More space for filters and details.

| Option | Description | Selected |
|--------|-------------|----------|
| Stats → Charts → Table | Top: 4 stat cards. Meio: bar + pie. Bottom: table. Overview-to-detail flow. | ✓ |
| Tabs por seção | Tabs: Overview, Charts, Top Consumers. Less scroll but requires clicks. | |
| Você decide | Claude chooses. | |

**User's choice:** Stats → Charts → Table

---

## Visualização de dados

| Option | Description | Selected |
|--------|-------------|----------|
| SVG inline manual | Gerar path SVG simples direto no HEEx. Zero dependência. | ✓ |
| Contex sparkline | Usar Contex.Sparkline. Pronto mas manutenção parada. | |
| Você decide | Claude chooses. | |

**User's choice:** SVG inline manual for sparklines

| Option | Description | Selected |
|--------|-------------|----------|
| Plox | Server-side SVG com componentes HEEx nativos. Ativo, feito para LiveView. | ✓ |
| Contex com boundary | Já no stack recomendado. Funcional mas parado. | |
| SVG manual | Zero dependência mas muito trabalho para bar+pie. | |
| Chart.js | N/A — violates zero-JS constraint | |

**User's choice:** Plox
**Notes:** User asked about Chart.js — explained it violates the "Zero JS frameworks" constraint. Researched alternatives and found Plox (server-side SVG, HEEx components, active since 2024). User approved Plox as Contex replacement.

---

## Filtros e período

| Option | Description | Selected |
|--------|-------------|----------|
| Presets + custom | Buttons: 7d, 30d, 90d, 1y + date range picker with native HTML5 inputs. | ✓ |
| Só presets | Only 7d, 30d, 90d, 1y. Simpler but less flexible. | |
| Dropdown de períodos | Select dropdown with named periods. Compact but less visual. | |

**User's choice:** Presets + custom date range

| Option | Description | Selected |
|--------|-------------|----------|
| Globais no topo | One filter bar at page top affects all widgets simultaneously. | ✓ |
| Por widget | Each widget has its own filters. More complex. | |
| Global + override | Global by default, per-widget override. Maximum flexibility but complex UI. | |

**User's choice:** Global filters at page top

| Option | Description | Selected |
|--------|-------------|----------|
| Segue o período global | Sparkline shows same period as global filter. Consistent. | ✓ |
| Sempre 7 dias | Fixed 7-day sparkline regardless of global filter. | |
| Toggle 7d/30d no card | Mini toggle per card. More control but visual complexity. | |

**User's choice:** Sparkline follows global period

---

## Dados e Store API

| Option | Description | Selected |
|--------|-------------|----------|
| Client-side via Store API | Fetch raw records, aggregate in Elixir. Consistent with Phase 2. | ✓ |
| Novo módulo CostAggregator | Dedicated module for aggregations. More testable. | |
| Cache com ETS | Fetch once, cache with TTL. Faster but cache invalidation complexity. | |

**User's choice:** Client-side via Store API

| Option | Description | Selected |
|--------|-------------|----------|
| Decimal end-to-end | StoreAdapter returns Decimal. All aggregations use Decimal. Float only at SVG render. | ✓ |
| Você decide | Claude ensures COST-07 compliance pragmatically. | |

**User's choice:** Decimal end-to-end

| Option | Description | Selected |
|--------|-------------|----------|
| Sim, módulo separado | CostAggregator with pure functions. CostsLive orchestrates. Testable without Store. | ✓ |
| Direto no LiveView | Private functions in CostsLive. Fewer files but coupled. | |
| Você decide | Claude chooses. | |

**User's choice:** Separate CostAggregator module

---

## Claude's Discretion

- Stat card visual design (colors, icons, sizing)
- Chart color palette and styling
- Top consumers table column widths and responsive behavior
- Empty state design
- Loading states
- Number formatting
- Bar chart granularity mapping

## Deferred Ideas

- Server-side aggregation in Store — defer until scale >10k records
- Cost data export (CSV/JSON) — future enhancement
- Cost alerts/thresholds — out of scope for v1
- Per-request cost breakdown — depends on Store granularity
- ETS cache layer — premature optimization
