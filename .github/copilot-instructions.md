# Copilot Instructions For DCS-AccMod

## Mandatory First Read For Any Agent

Before proposing code changes, read these files in order:

1. `memory/README.md`
2. `memory/mission-overview.md`
3. `memory/pitfalls-and-debugging.md`
4. `memory/workspace-doc-index.md`

Then inspect target code/docs.

## Working Rules

- Treat `memory/` as the project-specific chatbot context source.
- Prefer navigating `DCS-SRS-AccMod.lua` via `SECTION:` headers documented in `memory/mission-overview.md`.
- Keep runtime-path awareness: Saved Games runtime copies can diverge from repo files.
- When adding major systems or refactoring mission architecture, update `memory/mission-overview.md` and relevant memory docs in the same change.

## Documentation Expectations

When introducing behavior changes:

- Update at least one of:
  - `memory/mission-overview.md`
  - `memory/pitfalls-and-debugging.md`
  - `memory/workspace-doc-index.md`
- Add/maintain stable section headers in large Lua modules when practical.
