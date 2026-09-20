#!/bin/bash
# One-time setup of the secrets used by .github/workflows/release.yml (in the `release` GitHub
# Environment), and of the local notarization config used by Scripts/release.sh.
#
# Usage:
#   Scripts/setup-release-secrets.sh \
#       --p12 ~/path/DeveloperID.p12 --p12-password-file ~/path/p12_password.txt \
#       --asc-key ~/path/AuthKey_XXXXXXXXXX.p8 \
#       (--asc-issuer <issuer-uuid> | --asc-issuer-file <file>) \
#       [--team-id TEAMID] [--env release] [--repo owner/name]
#
# The issuer ID is in App Store Connect → Users and Access → Integrations → App Store Connect API
# (prefer --asc-issuer-file so it does not land in the shell history). Nothing is printed except
# confirmations; values go straight to `gh secret set` (stdin) and to
# ~/.config/quickreminder/notary.env (mode 600).
set -euo pipefail

P12=""; P12_PW_FILE=""; ASC_KEY=""; ASC_ISSUER=""; REPO=""; ENV_NAME="release"; TEAM_ID=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --p12) P12="$2"; shift 2 ;;
        --p12-password-file) P12_PW_FILE="$2"; shift 2 ;;
        --asc-key) ASC_KEY="$2"; shift 2 ;;
        --asc-issuer) ASC_ISSUER="$2"; shift 2 ;;
        --asc-issuer-file) ASC_ISSUER="$(tr -d '[:space:]' < "$2")"; shift 2 ;;
        --team-id) TEAM_ID="$2"; shift 2 ;;
        --env) ENV_NAME="$2"; shift 2 ;;
        --repo) REPO="$2"; shift 2 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done
for v in P12 P12_PW_FILE ASC_KEY ASC_ISSUER; do
    [[ -n "${!v}" ]] || { echo "error: --$(echo "$v" | tr '[:upper:]_' '[:lower:]-') is required" >&2; exit 2; }
done
[[ -f "$P12" && -f "$P12_PW_FILE" && -f "$ASC_KEY" ]] || { echo "error: a given file does not exist" >&2; exit 1; }
[[ "$ASC_ISSUER" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo "error: issuer ID should be a UUID" >&2; exit 1; }
[[ -z "$TEAM_ID" || "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo "error: team ID should be 10 characters" >&2; exit 1; }

KEY_ID="$(basename "$ASC_KEY" .p8)"; KEY_ID="${KEY_ID#AuthKey_}"
[[ "$KEY_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo "error: cannot derive the key ID from '$ASC_KEY' (expected AuthKey_<10 chars>.p8)" >&2; exit 1; }
ASC_KEY_ABS="$(cd "$(dirname "$ASC_KEY")" && pwd)/$(basename "$ASC_KEY")"

GH_ARGS=()
[[ -n "$REPO" ]] && GH_ARGS+=(--repo "$REPO")
[[ -n "$ENV_NAME" ]] && GH_ARGS+=(--env "$ENV_NAME")
gh_set() { gh secret set "$1" ${GH_ARGS[@]+"${GH_ARGS[@]}"}; }

echo "▶ Setting GitHub secrets${REPO:+ on $REPO}${ENV_NAME:+ (environment: $ENV_NAME)}"
base64 < "$P12" | tr -d '\n' | gh_set MACOS_CERTIFICATE
gh_set MACOS_CERTIFICATE_PWD < "$P12_PW_FILE"
openssl rand -base64 24 | gh_set KEYCHAIN_PASSWORD
base64 < "$ASC_KEY" | tr -d '\n' | gh_set ASC_API_KEY_P8
printf '%s' "$KEY_ID" | gh_set ASC_KEY_ID
printf '%s' "$ASC_ISSUER" | gh_set ASC_ISSUER_ID
gh secret list ${GH_ARGS[@]+"${GH_ARGS[@]}"}

echo "▶ Writing ~/.config/quickreminder/notary.env for Scripts/release.sh"
umask 077
mkdir -p "$HOME/.config/quickreminder"
chmod 700 "$HOME/.config/quickreminder"
ENV_FILE="$HOME/.config/quickreminder/notary.env"
install -m 600 /dev/null "$ENV_FILE"
{
    printf 'ASC_KEY_PATH=%q\n' "$ASC_KEY_ABS"
    printf 'ASC_KEY_ID=%q\n' "$KEY_ID"
    printf 'ASC_ISSUER_ID=%q\n' "$ASC_ISSUER"
    [[ -n "$TEAM_ID" ]] && printf 'EXPECTED_TEAM_ID=%q\n' "$TEAM_ID"
} > "$ENV_FILE"
echo "done. Test with: Scripts/release.sh 0.1.0 --dry-run"
