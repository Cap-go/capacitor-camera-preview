## Maestro

This folder contains example-app regression flows for manual or CI-driven device checks.

### Smoke flow

`camera-preview-smoke.yaml` exercises the example app end to end:

- enables Android physical camera selection
- starts the camera modal
- refreshes live device info
- runs the built-in diagnostics panel
- flips camera, zooms in once, and closes the modal

### Run locally

1. `cd example-app`
2. `bun install`
3. `bun run build`
4. `bunx cap sync android`
5. Install the debug build on an emulator or device
6. From the repo root, run `bunx maestro test .maestro/camera-preview-smoke.yaml`
