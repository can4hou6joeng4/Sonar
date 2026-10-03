#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in run|--verify|--debug|--logs|--telemetry) ;; *) echo "Usage: $0 [--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;; esac
SONAR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SONAR_DERIVED="$SONAR_ROOT/build/macOS"
SONAR_APP="$SONAR_DERIVED/Build/Products/Debug/SonarMac.app"
SONAR_EXECUTABLE="$SONAR_APP/Contents/MacOS/SonarMac"

# Only stop a previous launch from this checkout's deterministic build path.
while read -r sonar_pid sonar_path; do
    if [[ "$sonar_path" == "$SONAR_EXECUTABLE" ]]; then kill "$sonar_pid"; fi
done < <(ps -axo pid=,comm=)

cd "$SONAR_ROOT"
xcodebuild -quiet -project Sonar.xcodeproj -scheme SonarMac \
    -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath "$SONAR_DERIVED" CODE_SIGNING_ALLOWED=NO build

# Ad-hoc signing is local only; it needs no development certificate or account.
codesign --force --deep --sign - "$SONAR_APP"
if [[ "$MODE" == "--debug" ]]; then exec lldb "$SONAR_EXECUTABLE"; fi
open -n "$SONAR_APP"
case "$MODE" in
    --verify)
        sleep 2
        ps -axo comm= | awk -v expected="$SONAR_EXECUTABLE" '$0 == expected {found=1} END {exit !found}'
        echo "SonarMac built and process launched: $SONAR_APP"
        ;;
    --logs|--telemetry)
        exec /usr/bin/log stream --info --style compact --predicate 'process == "SonarMac"'
        ;;
esac
