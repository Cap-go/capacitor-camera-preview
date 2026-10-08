#!/usr/bin/env bash
# Runs the Swift package unit tests (ios/Tests) on an available iPhone simulator.
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Skipping iOS unit tests: xcodebuild requires macOS."
  exit 0
fi

device_id="$(
  xcrun simctl list devices available --json | node -e '
    let raw = "";
    process.stdin.on("data", (chunk) => (raw += chunk));
    process.stdin.on("end", () => {
      const runtimes = JSON.parse(raw).devices;
      const ios = Object.keys(runtimes)
        .filter((key) => key.includes("SimRuntime.iOS"))
        .sort((a, b) => b.localeCompare(a, undefined, { numeric: true }));
      for (const key of ios) {
        const phone = runtimes[key].find((device) => device.isAvailable && device.name.startsWith("iPhone"));
        if (phone) {
          process.stdout.write(phone.udid);
          return;
        }
      }
    });
  '
)"

if [ -z "$device_id" ]; then
  echo "No available iPhone simulator found."
  exit 1
fi

echo "Running CapgoCameraPreview unit tests on simulator $device_id"
xcodebuild test \
  -scheme CapgoCameraPreview \
  -destination "platform=iOS Simulator,id=$device_id" \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO
