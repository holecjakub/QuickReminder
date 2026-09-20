#!/bin/bash
# One-time setup of the GitHub Actions secrets used by .github/workflows/release.yml,
# and of the local notarization config used by Scripts/release.sh.
#
# Usage:
#   Scripts/setup-release-secrets.sh \
#       --p12 ~/path/DeveloperID.p12 --p12-password-file ~/path/p12_password.txt \
#       --asc-key ~/path/AuthKey_XXXXXXXXXX.p8 --asc-issuer <issuer-uuid> [--repo owner/name]
#
# The issuer ID is in App Store Connect → Users and Access → Integrations → App Store Connect API.
# Nothing is printed except confirmations; values go straight to `gh secret set` and to
# ~/.config/quickreminder/notary.env (mode 600).
set -euo pipefail

P12=""; P12_PW_FILE=""; ASC_KEY=""; ASC_ISSUER=""; REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --p12) P12="$2"; shift 2 ;;
        --p12-password-file) P12_PW_FILE="$2"; shift 2 ;;
        --asc-key) ASC_KEY="$2"; shift 2 ;;
        --asc-issuer) ASC_ISSUER="$2"; shift 2 ;;
        --repo) REPO="$2"; shift 2 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done
for v in P12 P12_PW_FILE ASC_KEY ASC_ISSUER; do
    [[ -n "${!v}" ]] || { echo "error: --$(echo "$v" | tr '[:upper:]_' '[:lower:]-') is required" >&2; exit 2; }
done
[[ -f "$P12" && -f "$P12_PW_FILE" && -f "$ASC_KEY" ]] || { echo "error: a given file does not exist" >&2; exit 1; }
[[ "$ASC_ISSUER" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo "error: issuer ID should be a UUID" >&2; exit 1; }

KEY_ID="$(basename "$ASC_KEY" .p8)"; KEY_ID="${KEY_ID#AuthKey_}"
REPO_FLAG=(); [[ -n "$REPO" ]] && REPO_FLAG=(--repo "$REPO")

echo "▶ Setting GitHub secrets${REPO:+ on $REPO}"
base64 < "$P12" | tr -d '\n' | gh secret set MACOS_CERTIFICATE ${REPO_FLAG[@]+"${REPO_FLAG[@]}"}
gh secret set MACOS_CERTIFICATE_PWD ${REPO_FLAG[@]+"${REPO_FLAG[@]}"} < "$P12_PW_FILE"
openssl rand -base64 24 | gh secret set KEYCHAIN_PASSWORD ${REPO_FLAG[@]+"${REPO_FLAG[@]}"}
base64 < "$ASC_KEY" | tr -d '\n' | gh secret set ASC_API_KEY_P8 ${REPO_FLAG[@]+"${REPO_FLAG[@]}"}
printf '%s' "$KEY_ID" | gh secret set ASC_KEY_ID ${REPO_FLAG[@]+"${REPO_FLAG[@]}"}
printf '%s' "$ASC_ISSUER" | gh secret set ASC_ISSUER_ID ${REPO_FLAG[@]+"${REPO_FLAG[@]}"}
gh secret list ${REPO_FLAG[@]+"${REPO_FLAG[@]}"}

echo "▶ Writing ~/.config/quickreminder/notary.env for Scripts/release.sh"
mkdir -p "$HOME/.config/quickreminder"
umask 077
cat > "$HOME/.config/quickreminder/notary.env" <<EOF
ASC_KEY_PATH=$ASC_KEY
ASC_KEY_ID=$KEY_ID
ASC_ISSUER_ID=$ASC_ISSUER
EOF
echo "done. Test with: Scripts/release.sh 0.1.0 --dry-run"
