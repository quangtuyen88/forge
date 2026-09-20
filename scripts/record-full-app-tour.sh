#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/scripts/shared-simulator.sh"
DERIVED_DATA=${DERIVED_DATA:-/tmp/forge-video-tour-derived}
OUTPUT=${OUTPUT:-$ROOT/artifacts/regulift-full-feature-tour.mp4}
FLOW=${FLOW:-$ROOT/.maestro/full-video-tour.yaml}

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

mkdir -p "$(dirname "$OUTPUT")" /tmp/forge-e2e/shots
udid=$(shared_simulator_udid "$runtime" "$device_type")
video_pid=""

finish_video() {
  if [ -n "$video_pid" ] && kill -0 "$video_pid" >/dev/null 2>&1; then
    kill -INT "$video_pid" >/dev/null 2>&1 || true
    wait "$video_pid" >/dev/null 2>&1 || true
  fi
  video_pid=""
}

cleanup() {
  finish_video
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  echo "Shared tour simulator: $udid"
}
trap cleanup EXIT INT TERM

xcrun simctl boot "$udid" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$udid" -b
xcrun simctl uninstall "$udid" app.regulift >/dev/null 2>&1 || true
xcrun simctl install "$udid" "$app"
xcrun simctl privacy "$udid" grant microphone app.regulift >/dev/null 2>&1 || true
xcrun simctl ui "$udid" appearance dark
xcrun simctl ui "$udid" content_size medium

record_log=/tmp/regulift-record-video-$$.log
xcrun simctl io "$udid" recordVideo --codec=h264 --mask=black --force "$OUTPUT" >"$record_log" 2>&1 &
video_pid=$!
for _ in $(seq 1 50); do
  if grep -q "Recording started" "$record_log" 2>/dev/null; then break; fi
  sleep 0.1
done
sleep 1

set +e
if command -v gtimeout >/dev/null 2>&1; then
  gtimeout --signal=INT --kill-after=30 2100 maestro --device "$udid" test "$FLOW"
else
  maestro --device "$udid" test "$FLOW"
fi
maestro_status=$?
set -e
sleep 2
finish_video

if [ "$maestro_status" -ne 0 ]; then
  echo "Maestro tour failed with status $maestro_status" >&2
  exit "$maestro_status"
fi

if [ ! -s "$OUTPUT" ]; then
  echo "Video was not created: $OUTPUT" >&2
  exit 1
fi

echo "Full feature tour: $OUTPUT"
