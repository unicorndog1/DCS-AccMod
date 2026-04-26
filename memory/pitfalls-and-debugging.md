# Pitfalls And Debugging (Chatbot)

Consolidated from `claude.md` and legacy memory notes.

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
- Button behavior can be mode-specific in layer mode (suppression/cycle paths).

## Runtime Path Mismatch

- DCS loads service scripts from Saved Games, not directly from this repo root.
- If behavior does not match edits, diff the Saved Games runtime copy first.

## Mission Script Safety

- Mission env methods can be nil depending on context (`setHeading`, etc.).
- Prefer guarded calls and explicit `ERR:*` return payloads instead of hard script errors.

## UI Loader Fragility

- Manager dialog load failures can come from malformed dialog file contents.
- Keep nil guards around dialog spawn to avoid crashing when dialog returns nil.

## Layer Rendering Notes

- Filled circle rendering depends on `filled` field in Lua packet payload.
- Batch parser and label handling in OpenXR C++ layer have known historical pitfalls.
- In OpenXR dots-only mode, labels are now hard-disabled by setting `labelA = 0.0` in Lua and skipping zero-alpha labels in C++; if labels still appear, verify the loaded runtime DLL was rebuilt/deployed from `OpenXR-Layer/build/bin`.
- If OpenXR behavior is stale after rebuild, verify the actually loaded DLL path under `OpenXR-Layer/build/bin`.
- Unit detection (`UnitHighlightPanel:detectUnits`) collects all on-screen LOS-visible units, then keeps the top `maxDots` (default 50) sorted by `facingDot` (highest = closest to visual center).
- The player's own unit is excluded via `LoGetPlayerPlaneId()` and a 5m fallback radius — it must never appear as a dot since it is already in the player's FOV.
- "Show All" toggle (`AccModOverlayManager.showAllUnits`) bypasses the static/structure category filter (`valid` / `valid2` tables) but still excludes the player and respects the top-N visual-center cap.

## Performance Notes

- Layer updates in Lua are throttled in some paths (targeting lower update rates for mode 2).
- UDP batching exists for lower syscall overhead in layer packet transmission.

## Ignore Noise

- Known DCS/MIST rooftop scanner log spam should be ignored unless explicitly requested.
