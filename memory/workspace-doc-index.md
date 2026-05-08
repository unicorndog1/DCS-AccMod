# Workspace Document Index (Chatbot)

Use this as the first-pass map of existing repository documentation.

## Core Project

- `docs/README.md`: project overview, install/build, high-level feature map.
- `docs/setup/SETUP.md`: general setup guidance.
- `docs/setup/BUILD_GUIDE.md`: build flow details.
- `docs/internal/claude.md`: practical debugging checklist for OpenXR layer path.

## Mission/Gameplay Features

- `docs/features/DRAG_MOVE_FEATURE.md`: drag-move unit placer behavior and UX.
- `docs/features/HEADING_ROTATION_IMPLEMENTATION.md`: heading rotation implementation details.
- `docs/features/ACCJOYBRIDGE_INTEGRATION.md`: native joystick bridge integration notes.

## MFD Workstream

- `docs/mfd/MFD_RENDERING_PLAN.md`: architecture and phased plan.
- `docs/mfd/MFD_IMPLEMENTATION_PROGRESS.md`: current state and tracking.
- `docs/mfd/MFD_SETUP_GUIDE.md`: setup and operational steps.
- `docs/mfd/MFD_QUICK_REFERENCE.md`: short operational reference.
- `docs/mfd/MFD_INDEX.md`: MFD docs navigation.
- `docs/mfd/IMPLEMENTATION_SUMMARY.md`: completed implementation report.
- `docs/mfd/IMPLEMENTATION_CHECKLIST.md`: verification checklist.

## Native Components

- `native/AccJoyBridge/README.md`: joystick bridge internals.
- `native/MFDCapture/README.md`: capture library internals.
- `OpenXR-Layer/README.md`: OpenXR layer architecture and runtime behavior.
- `OpenXR-Layer/QUICKSTART.md`: quick OpenXR usage path.
- `OpenXR-Layer/BUILD_REQUIREMENTS.md`: prerequisites/build requirements.

## Automation Scripts

- `build-all.bat`: build entrypoint; also stages `release/` with prebuilt binaries and a binary-installable OpenXR layer package.
- `deploy.bat`: deployment entrypoint.
- `release-template/install.bat`: source-controlled one-shot release installer staged to `release/install.bat`.
- `setup-mfd-system.ps1`: MFD setup automation.
- `Scripts/rebuild_catalog_and_deploy.ps1`: catalog rebuild/deploy flow.

## Legacy Memory Imports

- `memory/migrated/preferences.md`
- `memory/migrated/dcs-runtime-paths.md`
- `memory/migrated/dcs-ui-debugging.md`
- `memory/migrated/openxr-layer-notes.md`
