# Pitfalls And Debugging (Chatbot)

Consolidated from `docs/internal/claude.md` and legacy memory notes.

## OpenXR Layer Verification

- In `dcs.log`, `XR_APILAYER_DCS_AccMod` must appear in available layers.
- If missing, check HKLM implicit layer registry path points at the intended JSON manifest.
- Layer log `%TEMP%\\DCS_AccMod_OpenXR.log` should show negotiation and frame traffic.
- If layer frames always show zero circles, verify VR mode is actually LAYER (`vrModeEnabled == 2`).

## VR Mode Behavior

- `vrModeEnabled` meanings:
  - `0`: OFF
  - `1`: ON (window overlay)
  - `2`: LAYER (OpenXR via UDP 7779)
- Only `vrModeEnabled == 2` sends circle packets to OpenXR layer.
- If `net.get_my_player_id()` differs from `net.get_server_id()`, AccMod treats the session as a multiplayer client connection and suppresses both the VR and flatscreen unit-highlighter overlays.
- Persistent bypass: set `multiplayerOverlayBypass = true` in `AccModManager.lua` to disable the multiplayer overlay restriction for testing.
- Verbose multiplayer diagnostics are code-gated by `MULTIPLAYER_OVERLAY_DEBUG_LOGGING` in the Lua module and are off by default.
- Button behavior can be mode-specific in layer mode (suppression/cycle paths).

## Runtime Path Mismatch

- DCS loads service scripts from Saved Games, not directly from this repo root.
- If behavior does not match edits, diff the Saved Games runtime copy first.
- `setup-mfd-system.ps1` now resolves the most recently updated `Saved Games\DCS*` profile by `Config\options.lua`; if the generated MFD template points at the wrong profile, check which DCS profile was modified most recently.
- The MFD setup script reads `graphics.multiMonitorSetup`, `graphics.width`, and `graphics.height` from Saved Games `Config\options.lua`; if those values are stale, open DCS once, save graphics settings, and rerun the script.
- The MFD setup script now writes VDD's `vdd_settings.xml`, but Windows display placement is still separate from the XML. If the right number of virtual monitors exists but the DCS exports land in the wrong place, fix their layout in Windows Display Settings and keep the generated MonitorSetup coordinates aligned with that layout.

## Mission Script Safety

- Mission env methods can be nil depending on context (`setHeading`, etc.).
- Prefer guarded calls and explicit `ERR:*` return payloads instead of hard script errors.

## UI Loader Fragility

- Manager dialog load failures can come from malformed dialog file contents.
- Keep nil guards around dialog spawn to avoid crashing when dialog returns nil.
- **Plugin entry.lua i18n crash:** Empty `_("")` translation calls in `declare_plugin()` metadata can cause DCS to crash on startup with `Scripts/i18n.lua:213: bad argument #1 to 'translate' (string expected, got nil)`. Use plain empty strings `""` instead of `_("")` for optional fields like `developerName`, `developerLink`, and `info`.
- **Mission Editor Options auto-discovery:** DCS Mission Editor automatically discovers and loads any `Options/` folder in service plugins, even without explicit registration in `entry.lua`. Empty or incomplete Options stub files will crash Game GUI startup with the i18n translate error. Delete the entire `Options/` folder from both repo and Saved Games until a real options page is implemented.

## Layer Rendering Notes

- Filled circle rendering depends on `filled` field in Lua packet payload.
- Batch parser and label handling in OpenXR C++ layer have known historical pitfalls.
- In OpenXR dots-only mode, labels are now hard-disabled by setting `labelA = 0.0` in Lua and skipping zero-alpha labels in C++; if labels still appear, verify the loaded runtime DLL was rebuilt/deployed from `OpenXR-Layer/build/bin`.
- If OpenXR behavior is stale after rebuild, verify the actually loaded DLL path under `OpenXR-Layer/build/bin`.
- Unit detection (`UnitHighlightPanel:detectUnits`) collects all on-screen LOS-visible units, then keeps the top `maxDots` (default 50) sorted by `facingDot` (highest = closest to visual center).
- The player's own unit is excluded via `LoGetPlayerPlaneId()` and a 5m fallback radius — it must never appear as a dot since it is already in the player's FOV.
- "Show All" toggle (`AccModOverlayManager.showAllUnits`) bypasses the static/structure category filter (`valid` / `valid2` tables) but still excludes the player and respects the top-N visual-center cap.
- If the overlay shows `No world data`, the Lua now distinguishes between `local player not fully spawned yet`, missing Export functions, and `multiplayer world object export unavailable in this session` instead of returning a generic nil-state message.

## Performance Notes

- Layer updates in Lua are throttled in some paths (targeting lower update rates for mode 2).
- UDP batching exists for lower syscall overhead in layer packet transmission.

## Ignore Noise

- Known DCS/MIST rooftop scanner log spam should be ignored unless explicitly requested.
