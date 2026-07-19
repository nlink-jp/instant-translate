#!/bin/sh
# codesign-darwin-app.sh — sign a macOS .app bundle with a Developer ID
# Application identity (Hardened Runtime + Apple timestamp + entitlements),
# or skip gracefully if codesigning is not possible.
#
# Usage:
#   codesign-darwin-app.sh <path-to-.app> [identity] [entitlements.plist]
#
# Identity defaults to "Developer ID Application" (matches any Developer
# ID Application certificate in the keychain). Override via 2nd arg or
# CODESIGN_IDENTITY env. Entitlements default to none (Hardened Runtime
# alone suffices for pure SwiftUI/AppKit — no WebKit JIT).
#
# Behaviour:
#   - Skips on non-Darwin hosts (no codesign tool)
#   - Skips with a one-line warning if no matching identity exists
#   - Recursively signs everything under .app/ via --deep so nested
#     binaries (the bundled CLI, frameworks) inherit the same identity

set -e

APP="${1:?Usage: $0 <path-to-.app> [identity] [entitlements.plist]}"
IDENTITY="${2:-${CODESIGN_IDENTITY:-Developer ID Application}}"
ENTITLEMENTS="${3:-${CODESIGN_ENTITLEMENTS:-}}"

if [ "$(uname)" != "Darwin" ]; then
  exit 0
fi

if [ ! -d "$APP" ]; then
  echo "[codesign-app] $APP not found or not a directory, skipping" >&2
  exit 0
fi

case "$APP" in
  *.app) ;;
  *)
    echo "[codesign-app] $APP is not an .app bundle, skipping" >&2
    exit 0
    ;;
esac

if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "[codesign-app] No '$IDENTITY' identity in keychain; $APP keeps its existing signature" >&2
  exit 0
fi

SIGN_ARGS="--force --deep --options runtime --timestamp --sign \"$IDENTITY\""
if [ -n "$ENTITLEMENTS" ]; then
  if [ ! -f "$ENTITLEMENTS" ]; then
    echo "[codesign-app] entitlements file not found: $ENTITLEMENTS" >&2
    exit 1
  fi
  SIGN_ARGS="$SIGN_ARGS --entitlements \"$ENTITLEMENTS\""
fi

eval codesign $SIGN_ARGS "\"$APP\""
codesign --verify --deep --strict "$APP"
echo "[codesign-app] Signed $APP with '$IDENTITY' (Hardened Runtime, timestamped${ENTITLEMENTS:+, entitlements})"
