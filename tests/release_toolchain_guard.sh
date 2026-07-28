#!/bin/bash
# Fails loudly unless the exact macOS release toolchain is in effect.
#
# The release archive is published as `UsageBar-<version>-macOS-arm64.zip`, and
# nothing in build.sh or Package.swift forces an architecture or an SDK: the
# binary is simply whatever the runner and the selected Xcode produce. A
# floating `macos-latest` label therefore silently decides the operating
# system, the Swift compiler and the SDK a release is built with — which is how
# the 2.0.0 local and CI executables ended up differing.
#
# So both the advisory CI lane and the tag-triggered release workflow run this
# script, and they select the toolchain the same way, through a job-level
# DEVELOPER_DIR. One definition, two callers, no drift.
#
# What is deliberately NOT pinned: the macOS patch version, the GitHub runner
# image build, Homebrew, git and every other preinstalled tool. Those move
# without changing the toolchain a release is built with, and pinning them
# would only produce noise.
set -euo pipefail

readonly EXPECTED_DEVELOPER_DIR="/Applications/Xcode_16.4.app/Contents/Developer"
readonly EXPECTED_ARCH="arm64"
readonly EXPECTED_MACOS_MAJOR="15"
readonly EXPECTED_XCODE_VERSION="16.4"
readonly EXPECTED_XCODE_BUILD="16F6"
readonly EXPECTED_SDK_VERSION="15.5"
readonly EXPECTED_SWIFT_FAMILY="6.1"

fail() {
    printf 'release toolchain guard: %s\n' "$1" >&2
    shift
    for detail in "$@"; do
        printf '  %s\n' "$detail" >&2
    done
    exit 1
}

# --- 1/2. the selected developer directory ---------------------------------

if [[ "${DEVELOPER_DIR:-}" != "$EXPECTED_DEVELOPER_DIR" ]]; then
    fail "DEVELOPER_DIR is not the pinned release toolchain." \
        "expected: $EXPECTED_DEVELOPER_DIR" \
        "actual  : ${DEVELOPER_DIR:-<unset>}" \
        "Set it at job level so the selection stays local to the job; never use sudo xcode-select."
fi

if [[ ! -d "$DEVELOPER_DIR" ]]; then
    fail "The pinned Xcode is not installed on this machine." \
        "missing: $DEVELOPER_DIR" \
        "If GitHub removed this Xcode from the image, update the pin deliberately rather than floating it."
fi

# --- 3. host architecture ---------------------------------------------------

actual_arch="$(uname -m)"
if [[ "$actual_arch" != "$EXPECTED_ARCH" ]]; then
    fail "The runner architecture is not $EXPECTED_ARCH." \
        "actual: $actual_arch" \
        "The published archive is named -arm64 and nothing cross-compiles, so the host architecture is the artifact's architecture."
fi

# --- 4. operating-system generation (major only; the patch floats) ----------

macos_version="$(sw_vers -productVersion)"
macos_major="${macos_version%%.*}"
if [[ "$macos_major" != "$EXPECTED_MACOS_MAJOR" ]]; then
    fail "The macOS generation is not $EXPECTED_MACOS_MAJOR." \
        "actual: $macos_version" \
        "Pin the runner label (macos-15), not macos-latest."
fi

# --- 5. Xcode version and build --------------------------------------------

xcodebuild_output="$(xcodebuild -version)"
xcode_version="$(printf '%s\n' "$xcodebuild_output" | awk '/^Xcode /{print $2; exit}')"
xcode_build="$(printf '%s\n' "$xcodebuild_output" | awk '/^Build version /{print $3; exit}')"

if [[ "$xcode_version" != "$EXPECTED_XCODE_VERSION" ]]; then
    fail "Xcode is not version $EXPECTED_XCODE_VERSION." \
        "actual: ${xcode_version:-<unreadable>}" \
        "$xcodebuild_output"
fi

if [[ "$xcode_build" != "$EXPECTED_XCODE_BUILD" ]]; then
    fail "Xcode is not build $EXPECTED_XCODE_BUILD." \
        "actual: ${xcode_build:-<unreadable>}" \
        "A different build of the same version still means a different compiler."
fi

# --- 6. macOS SDK -----------------------------------------------------------

sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
if [[ "$sdk_version" != "$EXPECTED_SDK_VERSION" ]]; then
    fail "The macOS SDK is not $EXPECTED_SDK_VERSION." \
        "actual: $sdk_version"
fi

# --- 7/8. Swift compiler ----------------------------------------------------

swift_output="$(swift --version 2>&1)"
swift_version="$(printf '%s\n' "$swift_output" | awk '/Apple Swift version /{for (i = 1; i <= NF; i++) if ($i == "version") {print $(i + 1); exit}}')"

if [[ -z "$swift_version" ]]; then
    fail "Could not read an Apple Swift version." "$swift_output"
fi

if [[ "$swift_version" != "$EXPECTED_SWIFT_FAMILY" && "$swift_version" != "$EXPECTED_SWIFT_FAMILY".* ]]; then
    fail "The Swift compiler is not in the $EXPECTED_SWIFT_FAMILY family." \
        "actual: $swift_version" \
        "$swift_output"
fi

swiftc_version="$(swiftc --version 2>&1 | awk '/Apple Swift version /{for (i = 1; i <= NF; i++) if ($i == "version") {print $(i + 1); exit}}')"
if [[ "$swiftc_version" != "$swift_version" ]]; then
    fail "swiftc does not match swift." \
        "swift : $swift_version" \
        "swiftc: ${swiftc_version:-<unreadable>}" \
        "Two toolchains are visible; the build would not be reproducible."
fi

# --- 9/10. everything resolves inside the selected Xcode --------------------

swift_path="$(xcrun --find swift)"
if [[ -z "$swift_path" ]]; then
    fail "xcrun could not find swift inside $DEVELOPER_DIR."
fi

sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
if [[ "$sdk_path" != "$DEVELOPER_DIR"/* ]]; then
    fail "The effective SDK does not belong to the pinned Xcode." \
        "sdk    : $sdk_path" \
        "expected under: $DEVELOPER_DIR" \
        "Another Xcode or a Command Line Tools installation is winning."
fi

# --- summary ----------------------------------------------------------------

cat <<SUMMARY
release toolchain guard: OK
  architecture : $actual_arch
  macOS        : $macos_version (generation $macos_major pinned; patch floats)
  DEVELOPER_DIR: $DEVELOPER_DIR
  Xcode        : $xcode_version ($xcode_build)
  Swift        : $swift_version ($swift_path)
  macOS SDK    : $sdk_version ($sdk_path)
SUMMARY
