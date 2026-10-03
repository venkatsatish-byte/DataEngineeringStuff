#!/usr/bin/env bash
# Builds the iPhone and Watch apps for the simulator, runs them with sample
# data and saves screenshots to docs/screenshots. Used by CI; also works
# locally on a Mac with Xcode and XcodeGen installed.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=docs/screenshots
LOGS=build/logs
mkdir -p "$OUT" "$LOGS"
BUNDLE_ID=com.example.glucosecompanion

xcodegen generate
# Report every compile error in one run instead of stopping at the first.
defaults write com.apple.dt.Xcode IDEBuildingContinueBuildingAfterErrors -bool YES

# Pick the newest available iPhone and Apple Watch simulators.
pick() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
kind = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
candidates = []
for runtime, items in devices.items():
    if kind + "-" not in runtime:
        continue
    version = [int(x) for x in runtime.rsplit(".", 1)[-1].split("-")[1:]]
    for d in items:
        name = d["name"]
        if kind == "iOS" and name.startswith("iPhone"):
            preferred = "Pro" in name and "Max" not in name
        elif kind == "watchOS" and name.startswith("Apple Watch"):
            preferred = "Series" in name
        else:
            continue
        candidates.append((version, preferred, d["udid"]))
print(max(candidates)[2] if candidates else "")
' "$1"
}

IPHONE=$(pick iOS)
WATCH=$(pick watchOS)
echo "iPhone simulator: $IPHONE"
echo "Watch simulator:  ${WATCH:-none}"

build() {
  local scheme=$1 destination=$2 log=$3
  if ! xcodebuild -project GlucoseCompanion.xcodeproj -scheme "$scheme" -configuration Debug \
       -destination "$destination" -derivedDataPath build/DerivedData \
       CODE_SIGNING_ALLOWED=NO build > "$LOGS/$log" 2>&1; then
    echo "::group::$scheme build errors"
    grep -E "error:" "$LOGS/$log" | sort -u | head -80 || true
    grep -A3 "The following build commands failed" "$LOGS/$log" || true
    echo "::endgroup::"
    return 1
  fi
  grep -cE "warning:" "$LOGS/$log" | xargs -I{} echo "$scheme built ({} warning lines)"
}

build GlucoseCompanion "id=$IPHONE" ios-build.log
if [ -n "$WATCH" ]; then
  build GlucoseCompanionWatch "id=$WATCH" watch-build.log
else
  build GlucoseCompanionWatch "generic/platform=watchOS Simulator" watch-build.log
fi

APP=build/DerivedData/Build/Products/Debug-iphonesimulator/GlucoseCompanion.app
echo "Embedded watch app:"; ls "$APP/Watch" 2>/dev/null || echo "  (none)"
echo "Embedded widget extension:"; ls "$APP/PlugIns" 2>/dev/null || echo "  (none)"

# iPhone screenshots.
xcrun simctl boot "$IPHONE" 2>/dev/null || true
xcrun simctl bootstatus "$IPHONE" -b > /dev/null
xcrun simctl status_bar "$IPHONE" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 || true
xcrun simctl install "$IPHONE" "$APP"

shot() {
  local name=$1; shift
  xcrun simctl terminate "$IPHONE" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$IPHONE" "$BUNDLE_ID" -demoMode YES "$@" > /dev/null
  sleep 6
  xcrun simctl io "$IPHONE" screenshot --type=png "$OUT/iphone-$name.png" > /dev/null
  sips -Z 1400 "$OUT/iphone-$name.png" > /dev/null
  echo "Captured iphone-$name.png"
}

shot 1-today     -initialTab today
shot 2-trends    -initialTab trends
shot 3-meals     -initialTab meals
shot 4-guide     -initialTab guide
shot 5-settings  -initialTab settings
shot 6-urgent    -initialTab today -showUrgentDemo YES
shot 7-onboarding -showOnboarding YES
xcrun simctl ui "$IPHONE" appearance dark
shot 8-today-dark -initialTab today
xcrun simctl ui "$IPHONE" appearance light

# Watch screenshot.
if [ -n "$WATCH" ]; then
  WATCH_APP=build/DerivedData/Build/Products/Debug-watchsimulator/GlucoseCompanionWatch.app
  xcrun simctl boot "$WATCH" 2>/dev/null || true
  xcrun simctl bootstatus "$WATCH" -b > /dev/null
  xcrun simctl install "$WATCH" "$WATCH_APP"
  xcrun simctl launch "$WATCH" "$BUNDLE_ID.watchkitapp" -demoMode YES > /dev/null
  sleep 8
  xcrun simctl io "$WATCH" screenshot --type=png "$OUT/watch-1-latest.png" > /dev/null
  echo "Captured watch-1-latest.png"
fi

ls -la "$OUT"
