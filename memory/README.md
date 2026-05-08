# Chatbot Memory Hub

Purpose: provide a single, repo-local context pack for any new coding agent/chatbot working on this mission.

## Read Order (Required)

1. `memory/mission-overview.md`
2. `memory/pitfalls-and-debugging.md`
3. `memory/workspace-doc-index.md`
4. `memory/organization-suggestions.md`

## Source of Truth

- Runtime behavior and architecture references in this folder are derived from:
  - `Mods/Services/DCS-AccWidg/Scripts/DCS-SRS-AccMod.lua`
  - `docs/internal/claude.md`
  - Existing docs in `docs/`
  - Legacy memory notes copied into `memory/migrated/`

## Maintenance Rules

- When adding/refactoring major mission systems, update `memory/mission-overview.md`.
- Prefer adding stable `SECTION:` headers in Lua before documenting internals.
- Keep this folder focused on agent-operational context, not end-user marketing docs.
