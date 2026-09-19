#!/bin/bash
# Local release: build → sign (Developer ID) → zip + DMG → notarize → staple → tag → GitHub Release.
#
# Usage:
#   Scripts/release.sh 1.0.0              full release (tags v1.0.0, pushes the tag, creates the release)
#   Scripts/release.sh 1.0.0 --pre        mark the GitHub release as a pre-release
#   Scripts/release.sh 1.0.0 --dry-run    build, sign, package and notarize, but no tag / push / release
#   Scripts/release.sh 1.0.0 --no-notarize  skip notarization (local smoke test only)
#
# Notarization credentials (App Store Connect API key), in order of precedence:
#   env ASC_KEY_PATH / ASC_KEY_ID / ASC_ISSUER_ID
#   ~/.config/quickreminder/notary.env   (KEY=VALUE lines with the same names)
#   env NOTARY_PROFILE                   (a `xcrun notarytool store-credentials` keychain profile)
#
# Signing identity: the first "Developer ID Application" certificate in the keychain,
# or SIGN_ID=<sha1> to pick one explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="QuickReminder"
VERSION="${1:-}"
[[ -n "$VERSION" ]] || { echo "usage: Scripts/release.sh <version> [--pre] [--dry-run] [--no-notarize]" >&2; exit 2; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]] || { echo "error: version must look like 1.2.3" >&2; exit 2; }
shift
PRERELEASE=0; DRY_RUN=0; NOTARIZE=1
for arg in "$@"; do
    case "$arg" in
        --pre) PRERELEASE=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --no-notarize) NOTARIZE=0 ;;
        *) echo "unknown flag: $arg" >&2; exit 2 ;;
    esac
done

TAG="v$VERSION"
DIST="build/dist"
APP="build/$APP_NAME.app"
ZIP="$DIST/$APP_NAME-$VERSION.zip"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

log() { printf '\033[1;34m▶ %s\033[0m\n' "$*"; }

# --- Preflight -------------------------------------------------------------------------------
if [[ $DRY_RUN -eq 0 ]]; then
    [[ -z "$(git status --porcelain)" ]] || { echo "error: working tree not clean" >&2; exit 1; }
    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then echo "error: tag $TAG already exists" >&2; exit 1; fi
    command -v gh >/dev/null || { echo "error: gh CLI required" >&2; exit 1; }
fi

if [[ -z "${SIGN_ID:-}" ]]; then
    SIGN_ID="$( { security find-identity -v -p codesigning 2>/dev/null || true; } | awk '/Developer ID Application/ {print $2; exit}')"
fi
[[ -n "$SIGN_ID" ]] || { echo "error: no 'Developer ID Application' identity in the keychain (or set SIGN_ID)" >&2; exit 1; }
export SIGN_ID

if [[ $NOTARIZE -eq 1 ]]; then
    if [[ -z "${NOTARY_PROFILE:-}" && -f "$HOME/.config/quickreminder/notary.env" ]]; then
        # shellcheck disable=SC1091
        set -a; source "$HOME/.config/quickreminder/notary.env"; set +a
    fi
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
    elif [[ -n "${ASC_KEY_PATH:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
        NOTARY_ARGS=(--key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
    else
        echo "error: notarization credentials missing — set ASC_KEY_PATH/ASC_KEY_ID/ASC_ISSUER_ID (or ~/.config/quickreminder/notary.env), or NOTARY_PROFILE, or pass --no-notarize" >&2
        exit 1
    fi
fi

# --- Build -----------------------------------------------------------------------------------
log "Building $APP_NAME $VERSION (Release, Developer ID $SIGN_ID)"
VERSION="$VERSION" CONFIGURATION=Release ./build.sh
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Authority=Developer ID|Timestamp=" || { echo "error: bundle is not Developer-ID signed with a timestamp" >&2; exit 1; }

# --- Package ---------------------------------------------------------------------------------
log "Packaging"
rm -rf "$DIST"; mkdir -p "$DIST"
ditto -c -k --keepParent "$APP" "$ZIP"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
codesign --force --sign "$SIGN_ID" --timestamp "$DMG"

# --- Notarize --------------------------------------------------------------------------------
if [[ $NOTARIZE -eq 1 ]]; then
    for artifact in "$ZIP" "$DMG"; do
        log "Notarizing $(basename "$artifact")"
        xcrun notarytool submit "$artifact" "${NOTARY_ARGS[@]}" --wait
    done
    # The zip cannot be stapled; staple the .app (then re-zip) and the DMG.
    xcrun stapler staple "$APP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun stapler staple "$DMG"
    log "Gatekeeper assessment"
    spctl -a -vv --type exec "$APP"
    spctl -a -vv --type open --context context:primary-signature "$DMG"
fi

shasum -a 256 "$ZIP" "$DMG" | tee "$DIST/SHA256SUMS.txt"

if [[ $DRY_RUN -eq 1 ]]; then
    log "Dry run complete — artifacts in $DIST"
    exit 0
fi

# --- Tag + GitHub Release --------------------------------------------------------------------
log "Tagging $TAG"
git tag -a "$TAG" -m "$APP_NAME $VERSION"
git push origin "$TAG"

NOTES_FILE="$(mktemp)"
if [[ -f CHANGELOG.md ]] && awk -v v="## $VERSION" '$0 ~ "^## " {p = ($0 ~ v)} p' CHANGELOG.md | grep -q .; then
    awk -v v="## $VERSION" '$0 ~ "^## " {p = ($0 ~ v)} p' CHANGELOG.md | tail -n +2 > "$NOTES_FILE"
else
    echo "QuickReminder $VERSION" > "$NOTES_FILE"
fi
{
    echo
    echo "Signed with Developer ID and notarized by Apple. Requires macOS 26."
    echo
    echo '```'; cat "$DIST/SHA256SUMS.txt"; echo '```'
} >> "$NOTES_FILE"

log "Creating GitHub release"
RELEASE_FLAGS=(--title "$APP_NAME $VERSION" --notes-file "$NOTES_FILE")
[[ $PRERELEASE -eq 1 ]] && RELEASE_FLAGS+=(--prerelease)
gh release create "$TAG" "$ZIP" "$DMG" "$DIST/SHA256SUMS.txt" "${RELEASE_FLAGS[@]}"
rm -f "$NOTES_FILE"
log "Done: $(gh release view "$TAG" --json url --jq .url)"
