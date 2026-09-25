#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/scripts/shared-simulator.sh"
DERIVED_DATA=${DERIVED_DATA:-/tmp/forge-progress-e2e-derived}

for command in xcodebuild xcrun maestro; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 127
  fi
done

runtime=$(xcrun simctl list runtimes | awk '/^iOS / && $0 !~ /unavailable/ { value=$NF } END { print value }')
device_type=$(xcrun simctl list devicetypes | awk -F '[()]' '/iPhone 17e/ { print $2; exit }')
if [ -z "$device_type" ]; then
  device_type=$(xcrun simctl list devicetypes | awk -F '[()]' '/iPhone 17/ { print $2; exit }')
fi
if [ -z "$runtime" ] || [ -z "$device_type" ]; then
  echo "No available iOS simulator runtime/device type." >&2
  exit 1
fi

xcodebuild \
  -project "$ROOT/App/Forge.xcodeproj" \
  -scheme Forge \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet build

app="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Forge.app"
if [ ! -d "$app" ]; then
  echo "Built app not found: $app" >&2
  exit 1
fi

# The owner runs QA on a named iPhone 14; pass UDID to reuse it.
udid=${UDID:-$(shared_simulator_udid "$runtime" "$device_type")}
cleanup() {
  if [ -z "${UDID:-}" ]; then
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  fi
  echo "Progress E2E simulator: $udid"
}
trap cleanup EXIT INT TERM

attempt=1
while :; do
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  set +e
  xcrun simctl bootstatus "$udid" -b
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    break
  fi
  if [ "$attempt" -ge 3 ]; then
    echo "Simulator failed to finish booting after $attempt attempts: $udid" >&2
    exit 1
  fi
  attempt=$((attempt + 1))
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  sleep 2
done

xcrun simctl uninstall "$udid" app.regulift >/dev/null 2>&1 || true
xcrun simctl install "$udid" "$app"
xcrun simctl launch "$udid" app.regulift --seed-demo >/dev/null
# `simctl launch` returns before app initialization completes; DemoSeed saves synchronously during
# initialization, so keep this seeded launch alive before Maestro relaunches the app.
sleep 3
xcrun simctl terminate "$udid" app.regulift >/dev/null 2>&1 || true
rm -rf /tmp/forge-e2e/shots
mkdir -p /tmp/forge-e2e/shots
maestro --device "$udid" test "$ROOT/.maestro/progress-redesign.yaml"
xcrun simctl terminate "$udid" app.regulift >/dev/null 2>&1 || true
xcrun simctl launch "$udid" app.regulift --demo-record >/dev/null
sleep 3
maestro --device "$udid" test "$ROOT/.maestro/progress-record-sheet.yaml"
