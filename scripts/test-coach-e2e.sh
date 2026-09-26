#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/scripts/shared-simulator.sh"
DERIVED_DATA=${DERIVED_DATA:-/tmp/forge-coach-e2e-derived}
port=${COACH_STUB_PORT:-8799}

for command in xcodebuild xcrun maestro node curl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 127
  fi
done

# Two Maestro drivers on one host answer for each other's UI queries.
other_drivers=$(pgrep -fl "test-without-building -xctestrun" || true)
if [ -n "$other_drivers" ]; then
  echo "Refusing to run: another Maestro driver is alive:" >&2
  printf '%s\n' "$other_drivers" >&2
  exit 1
fi

runtime=$(xcrun simctl list runtimes | awk '/^iOS / && $0 !~ /unavailable/ { value=$NF } END { print value }')
device_type=$(xcrun simctl list devicetypes | awk -F '[()]' '/iPhone 17e/ { print $2; exit }')
if [ -z "$device_type" ]; then
  device_type=$(xcrun simctl list devicetypes | awk -F '[()]' '/iPhone 17/ { print $2; exit }')
fi
if [ -z "$runtime" ] || [ -z "$device_type" ]; then
  echo "No available iOS simulator runtime/device type." >&2
  exit 1
fi

app="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Forge.app"
if [ "${SKIP_BUILD:-0}" = "1" ]; then
  if [ ! -d "$app" ]; then
    echo "SKIP_BUILD=1 but no existing build at $app" >&2
    exit 1
  fi
else
  xcodebuild \
    -project "$ROOT/App/Forge.xcodeproj" \
    -scheme Forge \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    -quiet build
fi

udid=$(shared_simulator_udid "$runtime" "$device_type")
stub_pid=
OUT=${OUT:-$ROOT/artifacts/coach-e2e/$(date +%Y%m%d-%H%M%S)}
mkdir -p "$OUT"

cleanup() {
  if [ -n "$stub_pid" ]; then
    kill "$stub_pid" >/dev/null 2>&1 || true
  fi
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  echo "Shared E2E simulator: $udid"
}
trap cleanup EXIT INT TERM

attempt=1
while :; do
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  set +e
  xcrun simctl bootstatus "$udid" -b
  boot_status=$?
  set -e
  if [ "$boot_status" -eq 0 ]; then
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
xcrun simctl ui "$udid" appearance "${APPEARANCE:-light}"
xcrun simctl uninstall "$udid" app.regulift >/dev/null 2>&1 || true
xcrun simctl install "$udid" "$app"

if curl -sf "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
  echo "Port $port is already serving a coach stub; stop it first (lsof -i :$port)." >&2
  exit 1
fi

node "$ROOT/e2e/coach-stub.mjs" > "$OUT/stub.log" 2>&1 &
stub_pid=$!
health_attempts=0
until curl -sf "http://127.0.0.1:$port/health" >/dev/null 2>&1; do
  health_attempts=$((health_attempts + 1))
  if [ "$health_attempts" -ge 10 ]; then
    echo "coach-stub did not answer /health within 10 s (log: $OUT/stub.log)" >&2
    exit 1
  fi
  sleep 1
done
if ! kill -0 "$stub_pid" 2>/dev/null; then
  echo "coach-stub exited before answering /health; stub log follows:" >&2
  cat "$OUT/stub.log" >&2
  exit 1
fi

# --planning-fixture wipes the store and seeds a 4-day plan; -coachServerURL points the app at
# the stub for this launch only (argument domain); -coachOnDevice keeps the on-device model away.
xcrun simctl terminate "$udid" app.regulift >/dev/null 2>&1 || true
xcrun simctl launch "$udid" app.regulift --planning-fixture=FPLAN -coachServerURL "http://127.0.0.1:$port" -coachOnDevice NO -coachAppSecret e2e-stub

if [ "${ONLY_VOICE:-0}" != "1" ]; then
  maestro --device "$udid" test -e OUT="$OUT" "$ROOT/e2e/coach-actions.yaml"
fi

# Voice mode hears the scripted swap question end to end.
xcrun simctl terminate "$udid" app.regulift >/dev/null 2>&1 || true
xcrun simctl launch "$udid" app.regulift --planning-fixture=FPLAN -coachServerURL "http://127.0.0.1:$port" -coachOnDevice NO -coachAppSecret e2e-stub -coachVoiceScript "My lower back is tired. Can I swap bent-over rows?"
maestro --device "$udid" test -e OUT="$OUT" "$ROOT/e2e/coach-voice.yaml"

# Voice mode says so when it heard nothing, and sends nothing.
xcrun simctl terminate "$udid" app.regulift >/dev/null 2>&1 || true
xcrun simctl launch "$udid" app.regulift --planning-fixture=FPLAN -coachServerURL "http://127.0.0.1:$port" -coachOnDevice NO -coachAppSecret e2e-stub -coachVoiceScript '" "'
maestro --device "$udid" test -e OUT="$OUT" "$ROOT/e2e/coach-voice-missed.yaml"

# Voice mode fails closed when the microphone is unavailable.
xcrun simctl terminate "$udid" app.regulift >/dev/null 2>&1 || true
xcrun simctl launch "$udid" app.regulift --planning-fixture=FPLAN -coachServerURL "http://127.0.0.1:$port" -coachOnDevice NO -coachAppSecret e2e-stub -voiceUnavailable YES
maestro --device "$udid" test -e OUT="$OUT" "$ROOT/e2e/coach-voice-mic-off.yaml"

# The guide source row under a server answer that carries sources.
xcrun simctl terminate "$udid" app.regulift >/dev/null 2>&1 || true
xcrun simctl launch "$udid" app.regulift --planning-fixture=FPLAN -coachServerURL "http://127.0.0.1:$port" -coachOnDevice NO -coachAppSecret e2e-stub
maestro --device "$udid" test -e OUT="$OUT" "$ROOT/e2e/coach-sources.yaml"

# A pending card survives follow-up replies without a card; a stale one is cleared.
xcrun simctl terminate "$udid" app.regulift >/dev/null 2>&1 || true
xcrun simctl launch "$udid" app.regulift --planning-fixture=FPLAN -coachServerURL "http://127.0.0.1:$port" -coachOnDevice NO -coachAppSecret e2e-stub
maestro --device "$udid" test -e OUT="$OUT" "$ROOT/e2e/coach-card-kept.yaml"

echo "Coach and voice E2E passed. Screenshots: $OUT"
