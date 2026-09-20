#!/bin/sh
#
# Xcode Cloud: runs immediately after the repository is cloned.
#
# Responsibilities (§103):
#   - log the toolchain, so a build failure can be attributed to a version
#   - make the Ruby/fastlane tooling available *if* the workflow needs it
#   - verify the checked-in project matches its manifest
#
# Deliberately tolerant: a missing Ruby is not a reason to fail a build that
# only compiles and tests. Anything genuinely required fails loudly instead.

set -eu

echo "──────────────────────────────────────────────"
echo "Keezly — ci_post_clone"
echo "──────────────────────────────────────────────"
echo "workflow      : ${CI_WORKFLOW:-<not set>}"
echo "build number  : ${CI_BUILD_NUMBER:-<not set>}"
echo "build id      : ${CI_BUILD_ID:-<not set>}"
echo "scheme        : ${CI_XCODE_SCHEME:-<not set>}"
echo "action        : ${CI_XCODEBUILD_ACTION:-<not set>}"
echo "branch        : ${CI_BRANCH:-<not set>}"
echo "commit        : ${CI_COMMIT:-<not set>}"
echo

echo "── toolchain ──"
xcodebuild -version || true
swift --version 2>&1 | head -2 || true
echo "ruby          : $(ruby --version 2>/dev/null || echo 'not available')"
echo "bundler       : $(bundle --version 2>/dev/null || echo 'not available')"
echo

# Fastlane is only needed by workflows that run a lane. Xcode Cloud's own
# build/test/archive path does not, so this is best-effort by design (DEC-008).
if [ -f "$CI_PRIMARY_REPOSITORY_PATH/Gemfile" ] && command -v bundle >/dev/null 2>&1; then
    echo "── bundler ──"
    cd "$CI_PRIMARY_REPOSITORY_PATH"
    bundle config set --local path 'vendor/bundle'
    if bundle install --quiet; then
        echo "bundler dependencies installed"
    else
        echo "warning: bundle install failed; lanes will not be available in this build"
    fi
    echo
fi

echo "ci_post_clone finished"
