# Migrated From /memories/repo/openxr-layer-notes.md

- OpenXR circles require Lua packet `filled` field to match intended rendering.
- Check distance-based filtering in `sendCirclesToOpenXR` when markers are missing.
- Active implicit-layer registry entry often points to `OpenXR-Layer/build/bin/...` artifacts.
- Run `OpenXR-Layer/build.bat` from `OpenXR-Layer` working directory.
- Final copy can fail if Release DLL is locked by DCS/OpenXR runtime.
- Layer-mode button behavior is mode-specific and can intentionally suppress overlay while held.
- OpenXR and window modes use distinct render mode cycles; verify current VR mode first.
- If behavior appears stale, compare `build/bin` vs `build/bin/Release` DLL timestamps and content.
- Batch UDP parsing and parser null-termination details have historically caused subtle label/render bugs.
