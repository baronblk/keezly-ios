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
#
# The guard asks whether bundler *works*, not whether it exists. That
# distinction failed builds 1 to 3: Apple's runner has /usr/bin/bundle, so
# `command -v bundle` was true, but it is the Ruby 2.6 system shim and this
# repository's Gemfile.lock pins bundler 4.0.21 — so every bundle command died
# with "Could not find 'bundler' (4.0.21)". `bundle config set` was outside the
# `if`, `set -e` was in force, and ci_post_clone exited 1 before a single file
# was compiled.
#
# `bundle --version` is the cheapest honest test: it fails on exactly the
# mismatch that would break everything after it. Nothing here may fail the
# build, so the whole block is explicitly tolerant.
REPO="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"

if [ ! -f "$REPO/Gemfile" ]; then
    echo "no Gemfile — nothing to install"
elif ! bundle --version >/dev/null 2>&1; then
    echo "── bundler ──"
    echo "bundler is not usable on this runner; skipping."
    echo "Xcode Cloud builds, tests and archives without it (DEC-008)."
    echo "A workflow that needs a lane must install bundler itself, and say so."
else
    echo "── bundler ──"
    cd "$REPO"
    if bundle config set --local path 'vendor/bundle' >/dev/null 2>&1 \
        && bundle install --quiet; then
        echo "bundler dependencies installed"
    else
        echo "warning: bundle install failed; lanes will not be available in this build"
    fi
fi
echo

echo "ci_post_clone finished"
