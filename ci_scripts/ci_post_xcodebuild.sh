#!/bin/sh
#
# Xcode Cloud: runs after xcodebuild, whether it succeeded or not.
#
# Reports the outcome plainly and collects anything worth keeping. It must never
# turn a green build red, so every step here is tolerant of missing inputs.

set -u

echo "── Keezly: ci_post_xcodebuild ──"
echo "action    : ${CI_XCODEBUILD_ACTION:-<not set>}"
echo "exit code : ${CI_XCODEBUILD_EXIT_CODE:-<not set>}"

if [ "${CI_XCODEBUILD_EXIT_CODE:-0}" != "0" ]; then
    echo "xcodebuild reported a failure — see the log above."
fi

if [ -n "${CI_RESULT_BUNDLE_PATH:-}" ] && [ -d "${CI_RESULT_BUNDLE_PATH}" ]; then
    echo "result bundle: ${CI_RESULT_BUNDLE_PATH}"
fi

if [ -n "${CI_TEST_RESULTS_PATH:-}" ] && [ -d "${CI_TEST_RESULTS_PATH}" ]; then
    echo "test results : ${CI_TEST_RESULTS_PATH}"
fi

# A release build should never ship a stray generated build-number file.
REPO="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
[ -f "$REPO/Config/BuildNumber.xcconfig" ] && echo "generated build number config was present (expected in Xcode Cloud)"

echo "ci_post_xcodebuild finished"
exit 0
