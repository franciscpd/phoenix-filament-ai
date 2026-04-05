# Phase 1: Foundation + Chat - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-05
**Phase:** 01-foundation-chat
**Areas discussed:** Chat UX, Plugin config, Store adapter, Project scaffold

---

## Chat UX

| Option | Description | Selected |
|--------|-------------|----------|
| Bubble style | Balloons like WhatsApp/iMessage — user right, assistant left | |
| Full-width blocks | Full-width alternating blocks like ChatGPT/Claude | ✓ |
| You decide | Claude picks what makes sense for admin panel | |

**User's choice:** Full-width blocks
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Cursor piscando | Text appears gradually with blinking cursor (terminal style) | |
| Typing dots | Three animated dots until full response, then show all at once | |
| Progressive render | Text appears token-by-token WITH markdown rendered progressively | ✓ |

**User's choice:** Progressive render
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Half width (6 cols) | Half dashboard, as in PRD | |
| Full width (12 cols) | Full width — more space but dominates dashboard | |
| Configurável | Default 6 cols, configurable via column_span | ✓ |

**User's choice:** Configurable (default 6)
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Altura fixa com scroll | Fixed max height, messages scroll internally | ✓ |
| Expande com conteúdo | Widget grows with messages | |
| You decide | Claude picks | |

**User's choice:** Fixed height with scroll
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Prompt sugestivo | Inviting message with 2-3 clickable question suggestions | ✓ |
| Apenas input | Just the input field, minimalist | |
| System prompt visível | Shows configured system prompt as first message | |

**User's choice:** Suggestive prompt with clickable suggestions
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Inline no chat | Error message in chat thread with retry button | |
| Toast/flash | Flash notification at page top | |
| Both | Inline in chat + flash for critical errors | ✓ |

**User's choice:** Both — inline + flash for critical
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Sim, server-side | Syntax highlighting via Makeup | ✓ |
| Não, só monospace | Monospace with gray background, no coloring | |
| You decide | Claude decides | |

**User's choice:** Yes, server-side via Makeup
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Sim | Copy button via phx-hook | ✓ |
| Não | No copy button | |
| You decide | Claude decides | |

**User's choice:** Yes, copy button
**Notes:** None

---

## Plugin Config

| Option | Description | Selected |
|--------|-------------|----------|
| Tudo ligado | All features on by default | |
| Só chat | Only chat widget + page by default | |
| Progressive | Phase 1 features on, later features off until implemented | ✓ |

**User's choice:** Progressive defaults
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Fail at compile | NimbleOptions validates at compile time | ✓ |
| Fail at boot | Compiles ok, crashes at boot | |
| Graceful degrade | Boots with warnings, disables affected features | |

**User's choice:** Fail at compile
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Grupo 'AI' | All items under 'AI' group in sidebar | |
| Top-level items | Each feature as separate sidebar item | |
| Configurável | Default 'AI' group, overridable via nav_group opt | ✓ |

**User's choice:** Configurable (default "AI")
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Delegar ao PhoenixAI | Plugin doesn't touch API keys | |
| Aceitar como override | Accept :api_key in opts as convenience | |
| You decide | Claude decides most idiomatic approach | ✓ |

**User's choice:** You decide
**Notes:** None

---

## Store Adapter

| Option | Description | Selected |
|--------|-------------|----------|
| API única, backend transparent | Use only PhoenixAI.Store public API | |
| Backend-aware | Detect backend and adapt queries | |
| You decide | Claude decides based on Store API capabilities | ✓ |

**User's choice:** You decide
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Carregar tudo | Load all messages on open | |
| Lazy loading | Load last N messages, scroll-up loads more | ✓ |
| You decide | Claude decides | |

**User's choice:** Lazy loading
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Sim, banner visível | Warning banner on AI pages when ETS detected | |
| Só no log | Logger.warning on boot, no visible UI | |
| Configurável | Banner by default, disableable via ets_warning: false | ✓ |

**User's choice:** Configurable ETS warning
**Notes:** None

---

## Project Scaffold

| Option | Description | Selected |
|--------|-------------|----------|
| MIT | Most common for Elixir/Hex packages | ✓ |
| Apache 2.0 | Permissive with patent protection | |
| You decide | Claude picks | |

**User's choice:** MIT
**Notes:** None

---

**Elixir version:** Match phoenix_ai's requirement (user note: "Pegar a compativel com o phoenix_ai")

---

| Option | Description | Selected |
|--------|-------------|----------|
| GitHub Actions | CI with test, credo, dialyzer, format check | ✓ |
| Mínimo | Only mix test for now | |
| You decide | Claude sets up appropriate CI | |

**User's choice:** GitHub Actions (full)
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Público direto | Published as :phoenix_filament_ai on Hex | ✓ |
| Org privada | Published under an org | |

**User's choice:** Public direct
**Notes:** None

---

**Test app:** You decide (Claude's discretion)
**Version:** 0.1.0-dev, first release 0.1.0-rc.1

---

## Claude's Discretion

- API key handling approach
- Store adapter backend-awareness strategy
- Test app structure (separate repo vs subdir)
- Loading skeleton design
- Exact spacing and typography
- Auto-scroll implementation
- Streaming chunk batching/throttling

## Deferred Ideas

- Visual configuration UI — potential v0.2+ feature (user asked about this during discussion)
- Stop generation button — needs PhoenixAI cancellation API
- Message editing/regeneration — v2 feature
