#!/bin/sh

shared_simulator_udid() {
  runtime=$1
  device_type=$2
  name=${SIMULATOR_NAME:-Forge App E2E Explore}

  if [ -n "${SIMULATOR_UDID:-}" ]; then
    printf '%s\n' "$SIMULATOR_UDID"
    return
  fi

  existing=$(
    xcrun simctl list devices available -j | python3 -c '
import json, sys
name, runtime = sys.argv[1:3]
for device in json.load(sys.stdin).get("devices", {}).get(runtime, []):
    if device.get("name") == name and device.get("isAvailable", True):
        print(device["udid"])
        break
' "$name" "$runtime"
  )

  if [ -n "$existing" ]; then
    printf '%s\n' "$existing"
  else
    xcrun simctl create "$name" "$device_type" "$runtime"
  fi
}
