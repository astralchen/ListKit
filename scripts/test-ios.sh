#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_dir/.." && pwd)"
project_path="$repository_root/Examples/Examples.xcodeproj"
scheme="ExamplesUnitTests"
action="test"

print_usage() {
    printf '%s\n' \
        "Usage: scripts/test-ios.sh [--prepare | --no-build] [test-identifier ...]" \
        "" \
        "  default      Incrementally build and run ExamplesTests." \
        "  --prepare    Build the test products without running them." \
        "  --no-build   Reuse the last test build and only run tests." \
        "" \
        "Set LISTKIT_SIMULATOR_ID to force a specific simulator. Otherwise an" \
        "already booted iPhone/iPad is reused; a simulator is booted only when" \
        "none is currently running."
}

case "${1:-}" in
    --prepare)
        action="build-for-testing"
        shift
        ;;
    --no-build)
        action="test-without-building"
        shift
        ;;
    -h|--help)
        print_usage
        exit 0
        ;;
esac

devices="$(xcrun simctl list devices available)"
simulator_id="${LISTKIT_SIMULATOR_ID:-}"

if [[ -z "$simulator_id" ]]; then
    simulator_id="$(awk -F '[()]' '/(iPhone|iPad).*(Booted)/ { print $2; exit }' <<<"$devices")"
fi

did_boot_simulator="NO"
if [[ -z "$simulator_id" ]]; then
    simulator_id="$(awk -F '[()]' '/iPhone.*(Shutdown)/ { print $2; exit }' <<<"$devices")"
    if [[ -z "$simulator_id" ]]; then
        printf '%s\n' "No available iOS simulator was found." >&2
        exit 2
    fi
    xcrun simctl boot "$simulator_id"
    xcrun simctl bootstatus "$simulator_id" -b
    did_boot_simulator="YES"
fi

device_line="$(awk -v id="$simulator_id" 'index($0, id) { print; exit }' <<<"$devices")"
if [[ -z "$device_line" ]]; then
    printf 'Simulator %s is not available.\n' "$simulator_id" >&2
    exit 2
fi

if [[ "$did_boot_simulator" == "NO" && "$device_line" != *"(Booted)"* ]]; then
    xcrun simctl boot "$simulator_id"
    xcrun simctl bootstatus "$simulator_id" -b
    did_boot_simulator="YES"
fi

if [[ "$did_boot_simulator" == "YES" ]]; then
    printf 'Booted simulator once: %s\n' "$simulator_id"
else
    printf 'Reusing booted simulator: %s\n' "$simulator_id"
fi

xcodebuild_arguments=(
    "$action"
    -project "$project_path"
    -scheme "$scheme"
    -configuration Debug
    -destination "id=$simulator_id"
    -parallel-testing-enabled NO
    -maximum-parallel-testing-workers 1
    -maximum-concurrent-test-simulator-destinations 1
)

if [[ "$#" -eq 0 ]]; then
    xcodebuild_arguments+=("-only-testing:ExamplesTests")
else
    for test_identifier in "$@"; do
        xcodebuild_arguments+=("-only-testing:$test_identifier")
    done
fi

exec xcodebuild "${xcodebuild_arguments[@]}"
