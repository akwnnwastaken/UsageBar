#!/bin/zsh
# Writes ios/UsageBarMobileLab/Config/LocalSigning.xcconfig — the one untracked
# file that lets you build UsageBar Mobile for your own iPhone.
#
# It asks for two values, validates them, and writes a file. That is all.
#
# It does NOT:
#   * contact Apple, or any network service
#   * enrol you in the Apple Developer Program
#   * create certificates, App IDs or provisioning profiles
#   * run Xcode's automatic signing
#   * read, write or configure Tailscale
#   * modify project.pbxproj or any other tracked file
#
# Xcode creates the signing assets itself the first time you build to a device.
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
CONFIG_DIR="$PROJECT_DIR/ios/UsageBarMobileLab/Config"
TEMPLATE="$CONFIG_DIR/LocalSigning.example.xcconfig"
TARGET="$CONFIG_DIR/LocalSigning.xcconfig"

die() { print -u2 "error: $1"; exit 1; }

[[ -f "$TEMPLATE" ]] || die "template not found: $TEMPLATE"

if [[ -e "$TARGET" ]]; then
  print "A local signing file already exists:"
  print "  $TARGET"
  print ""
  print -n "Overwrite it? [y/N] "
  read -r reply
  [[ "$reply" == [yY] ]] || { print "Left unchanged."; exit 0; }
fi

# --- Team ID -----------------------------------------------------------------
#
# Not a secret, but it is account metadata, so it is read without echoing it
# back and never printed again — not in a confirmation line, not in the summary.
print "Apple Team ID (10 characters, from Xcode > Settings > Accounts)."
print -n "Team ID: "
read -r TEAM_ID
TEAM_ID="${TEAM_ID//[[:space:]]/}"
[[ "$TEAM_ID" =~ '^[A-Z0-9]{10}$' ]] \
  || die "a Team ID is exactly 10 uppercase letters and digits"

# --- Bundle namespace --------------------------------------------------------
print ""
print "Your own bundle namespace, in reverse-DNS form, for example"
print "  com.yourname.usagebarmobile"
print ""
print "It must be one no other Apple account has registered, so do not reuse"
print "com.usagebar.mobilelab and do not ship com.example... to a device."
print -n "Bundle namespace: "
read -r BUNDLE_BASE
BUNDLE_BASE="${BUNDLE_BASE//[[:space:]]/}"

[[ "$BUNDLE_BASE" =~ '^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*)+$' ]] \
  || die "a bundle identifier is dot-separated alphanumeric segments, each starting with a letter"
[[ "$BUNDLE_BASE" != "com.usagebar.mobilelab" ]] \
  || die "com.usagebar.mobilelab is the maintainer's namespace; choose your own"
case "$BUNDLE_BASE" in
  com.example|com.example.*)
    die "com.example.* is a documentation placeholder, not a namespace you own"
    ;;
esac

# --- Write -------------------------------------------------------------------
umask 077
cat > "$TARGET" <<CONFIG
// UsageBar Mobile — local signing configuration.
//
// Written by scripts/configure_ios_self_build.sh. Untracked and machine-local:
// do not commit it, and do not paste its contents into an issue or a pull
// request.
DEVELOPMENT_TEAM = $TEAM_ID
USAGEBAR_BUNDLE_ID_BASE = $BUNDLE_BASE
CONFIG
chmod 600 "$TARGET"

# Keep it untracked even if a future .gitignore forgets it. .git/info/exclude is
# local to the clone, so this changes nothing another contributor would receive.
GIT_DIR_PATH="$PROJECT_DIR/.git"
if [[ -d "$GIT_DIR_PATH" ]]; then
  EXCLUDE_FILE="$GIT_DIR_PATH/info/exclude"
  EXCLUDE_LINE="ios/UsageBarMobileLab/Config/LocalSigning.xcconfig"
  mkdir -p "$GIT_DIR_PATH/info"
  if ! grep -qxF "$EXCLUDE_LINE" "$EXCLUDE_FILE" 2>/dev/null; then
    print "$EXCLUDE_LINE" >> "$EXCLUDE_FILE"
    print "Added the local config to .git/info/exclude."
  fi
fi

print ""
print "Wrote $TARGET"
print "  bundle namespace : $BUNDLE_BASE"
print "  app              : $BUNDLE_BASE"
print "  widgets          : $BUNDLE_BASE.widgets"
print "  tests            : $BUNDLE_BASE.tests"
print "  keychain group   : <team prefix>.$BUNDLE_BASE.shared"
print "  team ID          : stored in the file, not shown here"
print ""
print "Next: open ios/UsageBarMobileLab/UsageBarMobileLab.xcodeproj, select your"
print "iPhone, and build. Xcode registers the identifiers on first build."
