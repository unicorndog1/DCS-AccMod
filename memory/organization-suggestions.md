R# Organization Suggestions And Immediate Actions

This document contains structure improvements and what has already been implemented.

## Implemented In This Change

- Added stable mission section headers in `DCS-SRS-AccMod.lua` for chatbot navigation.
- Added repo-local `memory/` hub with required read order and consolidated pitfalls.
- Added `.github/copilot-instructions.md` to force agent bootstrap from this memory hub.

## Next Suggested Improvements

1. Split monolithic mission script by subsystem (incremental extraction):
   - `Scripts/AccMod/vr_mode.lua`
   - `Scripts/AccMod/manager_config.lua`
   - `Scripts/AccMod/mission_bridge.lua`
   - `Scripts/AccMod/unit_placer.lua`

2. Standardize section header contract in Lua:
   - `SECTION: <NAME>`
   - `Purpose: ...`
   - Optional `Inputs/Outputs` summary for complex flows.

3. Add one "operational runbook" doc for incident response:
   - Runtime logs to check
   - Expected signature lines
   - Recovery steps ordered by likelihood.

4. Add a lightweight architecture graph:
   - UI manager -> unit placer -> mission bridge -> mission env
   - UI manager -> VR toggle -> OpenXR UDP -> OpenXR layer renderer

5. Add a doc ownership tag to major markdown files:
   - `Owner:` and `Last validated against code:`

## Suggested Naming Convention For New Docs

- `memory/mission-overview.md` (system map)
- `memory/pitfalls-and-debugging.md` (gotchas)
- `memory/workspace-doc-index.md` (doc router)
- `memory/runbook-*.md` (task playbooks)
