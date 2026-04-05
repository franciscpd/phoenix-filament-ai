# CLAUDE.md

## .planning/ — Single Source of Truth

All planning artifacts MUST go in `.planning/`. Never outside it.

```
.planning/
└── phases/
    └── {N}-{slug}/          ← one folder per GSD phase (e.g. 01-auth)
        ├── DISCUSS.md        ← gsd:discuss output
        ├── BRAINSTORM.md     ← superpowers:brainstorm output
        ├── PLAN.md           ← superpowers:write-plan output
        ├── PROGRESS.md       ← superpowers:execute-plan tracking
        └── VERIFY.md         ← superpowers:requesting-code-review output
```

Before writing any artifact, MUST identify the active GSD phase and resolve its folder: `.planning/phases/{N}-{slug}/`. Create the folder if it does not exist. All Superpowers outputs for that phase go inside it.

---

## Workflow — Follow This Order Exactly

```
gsd:discuss → brainstorm → write-plan → execute-plan → gsd:verify
```

> `$PHASE` = active GSD phase folder, e.g. `.planning/phases/01-auth`

### Phase 1 — discuss
- Trigger: any new feature, task or bug with unclear scope
- MUST capture: requirements, scope, what's out of scope, priority
- MUST save output to `$PHASE/DISCUSS.md`
- MUST NOT proceed without explicit user approval

### Phase 2 — brainstorm
- Trigger: automatically after discuss approval
- MUST invoke `/superpowers:brainstorm` using `$PHASE/DISCUSS.md` or `$PHASE/{N}-CONTEXT.md` as context
- Focus: technical approach, architecture, trade-offs, Laravel patterns
- MUST save output to `$PHASE/BRAINSTORM.md`
- MUST NOT proceed without explicit user approval

### Phase 3 — write-plan
- Trigger: automatically after brainstorm approval
- MUST invoke `/superpowers:write-plan` using `$PHASE/DISCUSS.md` or `$PHASE/{N}-CONTEXT.md` + `$PHASE/BRAINSTORM.md` as input
- Output MUST include: affected files, atomic tasks, verify commands, commit messages
- MUST save output to `$PHASE/PLAN.md`
- MUST NOT proceed without explicit user approval

### Phase 4 — execute-plan
- Trigger: automatically after plan approval
- MUST invoke `/superpowers:execute-plan` using `$PHASE/PLAN.md`
- MUST follow TDD: write failing test → implement → pass (RED → GREEN → REFACTOR)
- MUST track progress in `$PHASE/PROGRESS.md`
- MUST commit atomically per logical task immediately after verify passes

### Phase 5 — verify
- Trigger: automatically after execute-plan completes
- MUST invoke `/superpowers:requesting-code-review`
- MUST run `php artisan test && php artisan pint` — nothing is done without passing evidence
- MUST save output to `$PHASE/VERIFY.md`


## Skip Rules

| Situation | Skip |
|---|---|
| Scope is already clear | Skip discuss, start at brainstorm |
| Approach is already clear | Skip brainstorm, start at write-plan |
| Small well-defined task | Skip discuss + brainstorm, start at write-plan |
| Known bug with clear fix | Use `/superpowers:systematic-debugging` directly |

---

## Commits

```
type(scope): description
```
Types: `feat | fix | refactor | test | docs | style | chore`
One commit per logical task. Never commit broken code.

---

## Rules

- Bugs before features. Max 2–3 WIP tasks.
- Never deploy without explicit approval.
- Never skip phases without a skip rule justifying it.
- Always ask when scope or approach is unclear.

<!-- GSD:project-start source:PROJECT.md -->
## Project

**phoenix_filament_ai**

`phoenix_filament_ai` is a Hex package that works as a PhoenixFilament plugin, adding AI capabilities to admin panels. It connects PhoenixFilament (declarative UI) with PhoenixAI (AI runtime) and PhoenixAI.Store (conversation persistence), enabling developers to go from a configured store to a complete AI interface — chat with streaming, conversation history, cost dashboard, and event log — with a single plugin declaration.

**Core Value:** From a configured `phoenix_ai_store` to a complete AI admin interface in minutes — chat, conversations, cost visibility, and audit trail — all declarative and extensible via PhoenixFilament's plugin API.

### Constraints

- **Tech stack**: Elixir/Phoenix/LiveView — must follow OTP conventions and Phoenix patterns
- **Dependencies**: Only `phoenix_filament`, `phoenix_ai`, `phoenix_ai_store` as runtime deps. Dev deps: `ex_doc`, `credo`, `dialyxir`
- **No JS frameworks**: Zero additional JavaScript frameworks — LiveView + HEEx only
- **Backend-agnostic**: Must work with both ETS and Ecto store backends
- **Plugin API contract**: Must implement PhoenixFilament.Plugin behaviour exactly
- **Markdown rendering**: Server-side with Earmark, no client-side JS renderers
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Context
## Recommended Stack
### Runtime Dependencies (shipped with the plugin)
| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| `phoenix_filament` | `~> 0.1` | Plugin host — panel UI, widgets, nav, routes | Required by the plugin contract |
| `phoenix_ai` | `~> 0.3` | AI runtime — streaming via Finch SSE, provider abstraction | Core integration target |
| `phoenix_ai_store` | `~> 0.1` | Conversation persistence, cost tracking, event log | Core integration target |
| `nimble_options` | `~> 1.1` | Config schema validation and self-documenting opts | Industry standard for Elixir library opts. v1.1.1 is current. Used by Ecto, Broadway, Oban, etc. |
| `mdex` | `~> 0.12` | Server-side Markdown to HTML with streaming fragment support | Replaces Earmark. 81x faster (Rust NIF via comrak), built-in XSS sanitization via ammonia, native LiveView HEEx integration, `streaming: true` for incomplete markdown fragments during AI token streaming. v0.12.0 is current. |
| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| `contex` | `~> 0.5` | Server-side SVG charts (bar, sparkline) for cost dashboard | Only zero-JS chart lib in the ecosystem. Stale (last release May 2023) but functional. Isolate behind a module boundary. |
### Dev / Test Dependencies (not shipped)
| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| `ex_doc` | `~> 0.34` | HTML + EPUB + Markdown (llms.txt) docs generation | Standard for Hex packages. v0.40.1 is current. |
| `credo` | `~> 1.7` | Static code analysis, style consistency | v1.7.17 current. Consistent team coding style. |
| `dialyxir` | `~> 1.4` | Dialyzer type checking via mix tasks | v1.4.7 current. Catches type errors and unreachable code before runtime. |
| `excoveralls` | `~> 0.18` | Test coverage reports with coveralls.io integration | v0.18.5 current. PRD targets >80% coverage. |
### Mix Task Installer Dependency (dev + test, not shipped as runtime)
| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| `igniter` | `~> 0.7` | AST-based code patching for `mix phoenix_filament_ai.install` | v0.7.2 is current (Jan 2026). AST manipulation instead of regex/string hacks. Used by Phoenix 1.8 generators and Ash framework. Composable mix tasks. |
## Platform Versions
| Platform | Version | Notes |
|----------|---------|-------|
| Elixir | `~> 1.15` | Minimum for Igniter; `~> 1.17` recommended for full compat |
| Erlang/OTP | `~> 26` | Required for Elixir 1.15+ |
| Phoenix LiveView | `~> 1.1` | v1.1.28 current. Needed for colocated hooks feature |
| Phoenix | `~> 1.8` | v1.8.5 current. Required by LiveView 1.1 |
## Key Technology Decisions
### 1. MDEx over Earmark for Markdown
- **AI streaming support**: `MDEx.new(streaming: true)` handles incomplete markdown fragments as tokens arrive. Earmark requires a complete document before parsing. This is architectural — without it, you'd need to defer all rendering until streaming completes (bad UX) or accept garbled output mid-stream.
- **Performance**: 81x faster (0.11ms vs 9ms per parse), 2770x less memory. Irrelevant for cold docs but significant when rendering every token in a streaming response.
- **XSS built-in**: ammonia (Rust) handles sanitization. No second dependency (`html_sanitize_ex`) needed.
- **Native HEEx**: `MDEx.to_heex/2` returns a `Phoenix.LiveView.Rendered` struct — no `raw/1` workaround needed, change tracking works correctly.
- **Precompiled NIF**: Ships precompiled binaries for `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`. No Rust toolchain needed in host app.
### 2. handle_info for AI Streaming, Not LiveView Streams
# Stream handler — called by PhoenixAI's on_chunk callback
### 3. Contex for Charts (with isolation caveat)
### 4. NimbleOptions for Config Validation
### 5. Igniter for Mix Task Installer
## Alternatives Considered
| Category | Recommended | Rejected Alternative | Why Rejected |
|----------|-------------|---------------------|--------------|
| Markdown | `mdex ~> 0.12` | `earmark ~> 1.5` | No streaming support for incomplete fragments; 81x slower; no built-in XSS sanitization; no native HEEx integration |
| HTML Sanitization | Built into MDEx | `html_sanitize_ex ~> 1.4` | Redundant — MDEx/ammonia handles this |
| Charts | `contex ~> 0.5` | `vega_lite` | Requires JavaScript client rendering — violates zero-JS constraint |
| Charts | `contex ~> 0.5` | `chart_js` (via hooks) | Requires JavaScript — violates zero-JS constraint |
| Charts | `contex ~> 0.5` | `echarts` (via hooks) | Requires JavaScript — violates zero-JS constraint |
| Streaming Markdown | MDEx `streaming: true` | `phoenix_streamdown ~> 1.0.0-beta` | Beta software, additional dependency. Use MDEx streaming directly; apply `phx-update="ignore"` on completed blocks manually |
| Config Validation | `nimble_options ~> 1.1` | `norm` | NimbleOptions is ecosystem standard for library opts; Norm is for data validation schemas |
| Code Generation | `igniter ~> 0.7` | Manual EEx templates | Igniter produces idempotent AST patches; EEx templates overwrite and break on repeated installs |
## Installation (mix.exs for the plugin)
## What NOT to Use
| Library | Reason |
|---------|--------|
| `ecto` | Breaks storage-backend-agnostic contract. All data goes through PhoenixAI.Store API. |
| Any JS framework (Alpine.js, React, Vue) | Zero-JS constraint is core to the plugin's value prop |
| `html_sanitize_ex` | Redundant with MDEx/ammonia |
| `phoenix_streamdown` | Beta status; extra dependency; MDEx streaming handles the core use case |
| `vega_lite` / `kino` | Kino is Livebook-specific; VegaLite requires JavaScript |
| `earmark` | Replaced by MDEx for all reasons listed above |
| `norm` | Overkill for plugin config; NimbleOptions is the standard |
| `mox` | Use built-in ExUnit mock patterns for the Store adapter; Mox adds complexity |
## Confidence Summary
| Area | Confidence | Notes |
|------|------------|-------|
| Core framework (Phoenix/LiveView) | HIGH | Official docs, v1.1.28 current |
| MDEx for Markdown | HIGH | Official docs, v0.12.0, actively maintained 2026 |
| NimbleOptions for config | HIGH | Official docs, v1.1.1, ecosystem standard |
| Igniter for installer | HIGH | Official docs, v0.7.2, Jan 2026 release |
| handle_info streaming pattern | HIGH | Multiple production examples confirmed |
| Contex for charts | MEDIUM | Functional but maintenance paused May 2023 |
| PhoenixFilament plugin API | LOW | Package not yet publicly indexed on Hex; API described in PRD references local source files. Must be verified against actual source before implementation. |
| PhoenixAI / PhoenixAI.Store | LOW | Same — pre-release packages not on public Hex index. API contracts from PRD need direct source verification. |
## Sources
- [Phoenix LiveView v1.1.28 docs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html)
- [MDEx v0.12.0 docs](https://hexdocs.pm/mdex/MDEx.html)
- [MDEx GitHub](https://github.com/leandrocp/mdex) — streaming: true option, ammonia XSS protection
- [MDEx website](https://mdelixir.dev/) — performance benchmarks (81x vs Earmark)
- [NimbleOptions v1.1.1 docs](https://hexdocs.pm/nimble_options/)
- [Igniter v0.7.2 docs](https://hexdocs.pm/igniter/readme.html)
- [Contex v0.5.0 docs](https://hexdocs.pm/contex/Contex.html) — last release May 2023
- [Credo v1.7.17 docs](https://hexdocs.pm/credo/)
- [Dialyxir v1.4.7 docs](https://hexdocs.pm/dialyxir/readme.html)
- [ExCoveralls v0.18.5 docs](https://hexdocs.pm/excoveralls/ExCoveralls.html)
- [Phoenix LiveView 1.1 released](https://www.phoenixframework.org/blog/phoenix-liveview-1-1-released)
- [Streaming OpenAI with LiveView](https://fly.io/phoenix-files/streaming-openai-responses/)
- [phoenix_streamdown GitHub](https://github.com/dannote/phoenix_streamdown) — phx-update="ignore" pattern for streaming
- [html_sanitize_ex v1.4.3](https://hexdocs.pm/html_sanitize_ex/) — superseded by MDEx/ammonia
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, or `.github/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
