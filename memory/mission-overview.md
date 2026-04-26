# Mission Overview (Chatbot)

This file is a fast map of major mission systems for AI agents.

## Core Script

- Main script: `Mods/Services/DCS-AccWidg/Scripts/DCS-SRS-AccMod.lua`
- Scale: large, multi-system file (UI, VR/OpenXR, unit placement, bridge calls, persistence).

## Stable Section Headers in Code

Use these headers first when navigating the file:

1. `SECTION: JOYSTICK_UDP_LIFECYCLE` (around line 74)
   - UDP ingest socket lifecycle for joystick events (port 7778).
   - Handles reload-safe bind/rebind/cleanup behavior.

2. `SECTION: MISSION_ENV_SCRIPT_BRIDGE` (around line 360)
   - Wrap helper for mission-environment script execution (`a_do_script` payload wrapper).
   - Touch this when debugging bridge/mission execution paths.

3. `SECTION: VR_MODE_TOGGLE_AND_OPENXR_HANDOFF` (around line 885)
   - VR state machine for OFF -> ON overlay -> LAYER.
   - OpenXR availability gating, socket initialization, clear packet behavior, config persistence.

4. `SECTION: ACCMOD_OVERLAY_MANAGER_STATE` (around line 7240)
   - Singleton manager state (windows, modes, panel references, VR state, OpenXR status, keybind widgets).

5. `SECTION: MANAGER_CONFIG_PERSISTENCE` (around line 7426)
   - Load/save to `Config\\AccModManager.lua`.
   - Includes persisted `vrModeEnabled`, `showAllUnits`, keybinds, panel metadata, and unit placer state.

## High-Value Flows

- VR/OpenXR flow:
  - Toggle logic in `performVrModeToggle(...)`.
  - LAYER mode requires OpenXR layer availability and UDP path to port 7779.

- Mission environment execution flow:
  - `wrapMissionScript(...)` helper provides common payload shape.
  - Multiple features call bridge execution in mission env (unit queries, movement, draw-arg reads).

- Unit placer flow:
  - Uses mission-env queries to discover/move units.
  - Supports heading-aware move/rotate behavior (see related docs in index).

## Common Runtime Locations

- DCS log: `%USERPROFILE%\\Saved Games\\DCS\\Logs\\dcs.log`
- OpenXR layer log: `%TEMP%\\DCS_AccMod_OpenXR.log`
- Runtime service mod path (Saved Games): `%USERPROFILE%\\Saved Games\\DCS\\Mods\\Services\\DCS-AccWidg\\...`

## Update Checklist (When Architecture Changes)

1. Add/adjust `SECTION:` headers in Lua for any new major subsystem.
2. Update this file with the new section names and approximate line anchors.
3. Add pitfalls to `memory/pitfalls-and-debugging.md`.
4. Add new docs to `memory/workspace-doc-index.md`.
