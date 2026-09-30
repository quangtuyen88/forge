#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/scripts/shared-simulator.sh"
DERIVED_DATA=${DERIVED_DATA:-/tmp/forge-today-tiles-e2e-derived}

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
  xcrun simctl ui "$udid" appearance light >/dev/null 2>&1 || true
  if [ -z "${UDID:-}" ]; then
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  fi
  echo "Today tiles E2E simulator: $udid"
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

shots=${TODAY_TILES_SHOTS:-/tmp/forge-e2e/today-tiles}
rm -rf "$shots"; mkdir -p "$shots"
xcrun simctl ui "$udid" appearance light
# A fresh seeded install without today's check-in.
xcrun simctl uninstall "$udid" app.regulift >/dev/null 2>&1 || true
xcrun simctl install "$udid" "$app"
xcrun simctl launch "$udid" app.regulift --seed-demo --no-checkin-today --new-full-b >/dev/null
# `simctl launch` returns before DemoSeed saves; keep the seeded launch alive briefly.
sleep 6
xcrun simctl terminate "$udid" app.regulift >/dev/null 2>&1 || true
maestro --device "$udid" test -e SHOTS="$shots" "$ROOT/.maestro/today-tiles.yaml"
echo "Today tiles screenshots: $shots"
