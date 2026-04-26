# Migrated From /memories/repo/dcs-ui-debugging.md

- If manager window crashes with nil `managerWindow`, verify runtime `DCS-AccWidg-ManagerTabs.dlg` for malformed suffix/trailing backslashes.
- Keep nil guard after dialog spawn so startup logs clear loader failure instead of crashing.
- Declutter label mode currently applies to window overlay render path in `DCS-SRS-AccMod.lua`.
- If joystick input dies, inspect `dcs.log` for Lua hook crashes first; input loss can be secondary.
- In mission scripts, `Unit:setHeading()` can be nil; guarded fallback via `getPosition()` + basis update + `setPosition(...)` may be required.
- Use live camera basis vectors for cursor projection logic; fixed world axes break off-axis selection.
- Guard mission API calls (`setPosition`, `getHeading`, etc.) and return error payloads instead of hard-failing.
