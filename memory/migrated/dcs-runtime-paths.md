# Migrated From /memories/repo/dcs-runtime-paths.md

- DCS loads this service mod from Saved Games via `lfs.writedir()`, not directly from repo tree.
- Runtime path for manager UI changes: `%USERPROFILE%\\Saved Games\\DCS\\Mods\\Services\\DCS-AccWidg\\...`.
- If repo edits are not visible in DCS, compare Saved Games runtime copies first.
- Catalog snapshot builder supports Saved Games merge via `Scripts/rebuild_catalog_and_deploy.ps1 -IncludeSavedGamesMods`.
