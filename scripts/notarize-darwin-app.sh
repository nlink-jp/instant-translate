#!/bin/sh
# notarize-darwin-app.sh — submit a macOS .app bundle to Apple's notary
# service, wait for the verdict, then staple the ticket onto the .app.
#
# Usage:
#   notarize-darwin-app.sh <path-to-.app> [profile-name]
#
# Profile name defaults to NOTARY_PROFILE env, then to `nlink-jp-notary`.
# Credentials are stored once per machine via:
#
#   xcrun notarytool store-credentials nlink-jp-notary \
#       --key <p8>  --key-id <id>  --issuer <uuid>
#
# Behaviour:
#   - Skips on non-Darwin hosts
#   - Skips when the keychain profile isn't present (a one-line warning
#     is printed; the .app is left as-is)
#   - notarytool requires a zip/dmg/pkg container, so the .app is
#     wrapped in a temporary zip via `ditto -c -k --keepParent`. The
#     temp zip is discarded after submission — the ticket is keyed on
#     the .app's CDHash, not the container, so the discarded zip has
#     no further use.
#   - After Acceptance, `stapler staple` writes the ticket into the
#     .app so it launches without an online check on offline machines.
#     (CLI Mach-O binaries cannot be stapled — only bundle formats
#     can, which is why this is distinct from notarize-darwin.sh.)
#   - On Acceptance a `<app>.notarized` marker file is written beside
#     the bundle; `make verify-release` gates on it (and on the staple),
#     so the skip paths above cannot reach a release unnoticed.
#
# On failure prints the Apple-returned status and exits non-zero so a
# release pipeline halts.

set -e

APP="${1:?Usage: $0 <path-to-.app> [profile]}"
PROFILE="${2:-${NOTARY_PROFILE:-nlink-jp-notary}}"

if [ "$(uname)" != "Darwin" ]; then
  exit 0
fi

if [ ! -d "$APP" ]; then
  echo "[notarize-app] $APP not found or not a directory, skipping" >&2
  exit 0
fi

case "$APP" in
  *.app) ;;
  *)
    echo "[notarize-app] $APP is not an .app bundle, skipping" >&2
    exit 0
    ;;
esac

# Clear any marker from a previous run first, so no exit path below can
# leave a stale "notarized" verdict standing next to a rebuilt bundle.
rm -f "$APP.notarized"

# Profile probe (notarytool has no dedicated "is profile present"
# command; `history` returns quickly without uploading anything).
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  # The credential lives in the data-protection keychain, which is
  # unreadable while the screen is locked — the profile then *looks*
  # deleted (measured 2026-08: an unattended release batch died this
  # way mid-run). Diagnose that first; re-registering is never the fix.
  if ioreg -n Root -d1 2>/dev/null | grep -q '"IOConsoleLocked" = Yes'; then
    echo "[notarize-app] Keychain profile '$PROFILE' unreadable: the screen is locked" >&2
    echo "[notarize-app] (data-protection keychain items are unavailable while locked)." >&2
    echo "[notarize-app] Unlock the screen and re-run; the credential is intact." >&2
  else
    echo "[notarize-app] Keychain profile '$PROFILE' not found; $APP will ship un-notarised" >&2
    echo "[notarize-app] To enable, run once per machine:" >&2
    echo "[notarize-app]   xcrun notarytool store-credentials $PROFILE --key <p8> --key-id <id> --issuer <uuid>" >&2
  fi
  exit 0
fi

TMPZIP="$(mktemp -t notary-app)"
rm -f "$TMPZIP"
TMPZIP="${TMPZIP}.zip"
trap 'rm -f "$TMPZIP"' EXIT INT TERM

APP_DIR=$(dirname "$APP")
APP_NAME=$(basename "$APP")
(cd "$APP_DIR" && /usr/bin/ditto -c -k --keepParent "$APP_NAME" "$TMPZIP")

echo "[notarize-app] Submitting $APP to Apple notary service (this typically takes 30s-2m)..."
SUBMISSION_OUT=$(xcrun notarytool submit "$TMPZIP" --keychain-profile "$PROFILE" --wait 2>&1) || {
  echo "[notarize-app] $APP: submission failed" >&2
  echo "$SUBMISSION_OUT" >&2
  exit 1
}
echo "$SUBMISSION_OUT"

if ! printf '%s\n' "$SUBMISSION_OUT" | grep -q 'status: Accepted'; then
  echo "[notarize-app] $APP: notarisation did not succeed (see status above)" >&2
  exit 1
fi

echo "[notarize-app] Stapling notarisation ticket to $APP..."
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
# Success marker for verify-release. The fail-open above (shipping
# un-notarised when the profile probe fails) exists for contributors
# without credentials — but on the release machine it once shipped an
# un-notarised bundle with the pipeline green, because the probe failed
# (locked screen) and nothing downstream checked. verify-release now
# requires this marker, so the fail-open path can no longer reach a
# release unnoticed.
touch "$APP.notarized"
echo "[notarize-app] $APP: Accepted and stapled"
