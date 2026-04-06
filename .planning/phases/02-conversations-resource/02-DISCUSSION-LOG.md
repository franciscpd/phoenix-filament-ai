# Phase 2: Conversations Resource - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the discussion.

**Date:** 2026-04-06
**Phase:** 02-conversations-resource
**Mode:** discuss (interactive)
**Areas analyzed:** Architecture, Data Loading, Show Page, Export

## Gray Areas Identified

### 1. Architecture — Resource vs Custom LiveView
**Context:** PhoenixFilament.Resource is tightly coupled to Ecto via QueryBuilder, CRUD module, and pagination. StoreAdapter talks to PhoenixAI.Store which supports both ETS and Ecto backends.
**Options presented:**
- LiveView custom (Recommended) — Zero Ecto coupling, follows ChatLive pattern
- Resource with bridge adapter — Complex, fragile
- Resource for Ecto, fallback for ETS — More code, better per-backend performance
**User chose:** LiveView custom

### 2. Data Loading — Pagination & Filtering Strategy
**Context:** Store API has no pagination or search params. Current chat sidebar loads all conversations and filters client-side.
**Options presented:**
- Client-side with limit (Recommended) — In-memory, works to ~1000 conversations
- Server-side in Store — Better scale, requires Store API changes
- Hybrid — Client-side default with optional Store pagination
**User chose:** Client-side with limit

### 3. Show Page — Layout
**Context:** Need to display full message thread with metadata (cost, tokens, tags).
**Options presented:**
- Chat-style with metadata (Recommended) — Reuse MessageComponent, sidebar for metadata
- Timeline vertical — Audit-like, less chat-like
- Split view — Metadata top, thread bottom
**User chose:** Chat-style with metadata

### 4. Export — Format
**Context:** CONV-08 requires export capability.
**Options presented:**
- JSON + Markdown both — Programmatic + human-readable
- Only JSON — Minimal, Markdown derivable
- JSON + Markdown + CSV — Extra CSV for spreadsheet analysis
**User chose:** JSON + Markdown both

## Corrections Made

No corrections — all recommendations confirmed.
