#!/bin/sh
# Crew E2E against a real local server (F4). The fixture flow (.maestro/progress-crew.yaml)
# cannot catch posting/loading bugs, so this signs the app lifter in on a live
# `node server/dist/index.js` (dev ENV returns the email dev code), seeds Linh and Kenji over
# HTTP (scripts/crew-server-seed.py), runs .maestro/crew-server.yaml, then asserts through the
# server that the logged workout reached /social/crew and /social/feed.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/scripts/shared-simulator.sh"
DERIVED_DATA=${DERIVED_DATA:-/tmp/forge-crew-server-e2e-derived}
SIMULATOR_NAME=${SIMULATOR_NAME:-Forge Crew E2E}
PORT=${CREW_E2E_PORT:-8799}

for command in xcodebuild xcrun maestro node pnpm python3; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 127
  fi
done

# Two Maestro sessions on one host control each other's devices; refuse to be the second.
if pgrep -f "test-without-building -xctestrun" >/dev/null 2>&1 || pgrep -f "maestro test" >/dev/null 2>&1; then
  echo "Refusing to run: another Maestro session is already running on this host:" >&2
  pgrep -fl "test-without-building -xctestrun" >&2 || true
  pgrep -fl "maestro test" >&2 || true
  exit 2
fi

ART=${CREW_E2E_ART:-$HOME/.cache/forge-crew-e2e/run-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$ART"

server_pid=
udid=
cleanup() {
  if [ -n "$udid" ]; then
    xcrun simctl terminate "$udid" app.regulift >/dev/null 2>&1 || true
    if [ -z "${UDID:-}" ]; then
      xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    fi
  fi
  if [ -n "$server_pid" ]; then
    kill "$server_pid" >/dev/null 2>&1 || true
  fi
  echo "Crew server E2E simulator: $udid"
  echo "Crew server E2E artifacts: $ART"
}
trap cleanup EXIT INT TERM

pnpm --dir "$ROOT/server" run build
APP_SECRET=e2e-local PORT="$PORT" node "$ROOT/server/dist/index.js" >"$ART/server.log" 2>&1 &
server_pid=$!

# Wait for the port to answer /health (python3, so the script needs no curl).
health_attempts=0
until python3 -c 'import sys, urllib.request
try:
    urllib.request.urlopen("http://127.0.0.1:%s/health" % sys.argv[1], timeout=2).read()
except Exception:
    sys.exit(1)
' "$PORT"; do
  if ! kill -0 "$server_pid" 2>/dev/null; then
    echo "forge server exited before answering /health; log follows:" >&2
    cat "$ART/server.log" >&2
    exit 1
  fi
  health_attempts=$((health_attempts + 1))
  if [ "$health_attempts" -ge 30 ]; then
    echo "forge server did not answer /health within 30 s (log: $ART/server.log)" >&2
    exit 1
  fi
  sleep 1
done

python3 "$ROOT/scripts/crew-server-seed.py" seed \
  --base "http://127.0.0.1:$PORT" --secret e2e-local --out "$ART/seed.json"

runtime=$(xcrun simctl list runtimes | awk '/^iOS / && $0 !~ /unavailable/ { value=$NF } END { print value }')
device_type=$(xcrun simctl list devicetypes | awk -F '[()]' '/iPhone 17e/ { print $2; exit }')
if [ -z "$device_type" ]; then
  device_type=$(xcrun simctl list devicetypes | awk -F '[()]' '/iPhone 17/ { print $2; exit }')
fi
if [ -z "$runtime" ] || [ -z "$device_type" ]; then
  echo "No available iOS simulator runtime/device type." >&2
  exit 1
fi

# Signed ("Sign to Run Locally"): an unsigned simulator build silently drops Keychain writes, so
# the session token from sign-in never persists and every social call answers 401.
xcodebuild \
  -project "$ROOT/App/Forge.xcodeproj" \
  -scheme Forge \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY=- \
  -quiet build

app="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Forge.app"
if [ ! -d "$app" ]; then
  echo "Built app not found: $app" >&2
  exit 1
fi

udid=$(shared_simulator_udid "$runtime" "$device_type")

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

# Fresh install; one --seed-demo launch writes the local profile so the app opens on Today.
xcrun simctl uninstall "$udid" app.regulift >/dev/null 2>&1 || true
xcrun simctl install "$udid" "$app"
xcrun simctl launch "$udid" app.regulift --seed-demo >/dev/null
sleep 3
xcrun simctl terminate "$udid" app.regulift >/dev/null 2>&1 || true

maestro --device "$udid" test -e ART="$ART" -e PORT="$PORT" "$ROOT/.maestro/crew-server.yaml"

# Verify over HTTP that the run reached the server (writes crew.json, feed.json, summary.txt).
python3 "$ROOT/scripts/crew-server-seed.py" check \
  --base "http://127.0.0.1:$PORT" --secret e2e-local --seed "$ART/seed.json" --out "$ART"

echo "Crew server E2E passed. Artifacts: $ART"
