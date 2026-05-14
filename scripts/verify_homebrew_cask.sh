#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CASK_FILE="$ROOT_DIR/Casks/quotabar.rb"
DEFAULT_TAP="chilohwei/quotabar"
CASK_NAME="quotabar"

usage() {
    cat <<USAGE
Usage: scripts/verify_homebrew_cask.sh <version> [--tap <owner/repo>] [--skip-brew]

Checks:
  1) SHA256 in Casks/quotabar.rb matches GitHub release asset.
  2) (default) brew fetch --cask from the tap can download and verify successfully.

Examples:
  scripts/verify_homebrew_cask.sh <version>
  scripts/verify_homebrew_cask.sh <version> --tap chilohwei/quotabar
  scripts/verify_homebrew_cask.sh <version> --skip-brew
USAGE
}

TAP="$DEFAULT_TAP"
SKIP_BREW=false
VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tap)
            TAP="${2:-}"
            if [[ -z "$TAP" ]]; then
                echo "Missing value for --tap" >&2
                exit 1
            fi
            shift 2
            ;;
        --skip-brew)
            SKIP_BREW=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            if [[ -n "$VERSION" ]]; then
                echo "Unexpected argument: $1" >&2
                usage >&2
                exit 1
            fi
            VERSION="$1"
            shift
            ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    usage >&2
    exit 1
fi

if [[ ! -f "$CASK_FILE" ]]; then
    echo "Missing cask file: $CASK_FILE" >&2
    exit 1
fi

cask_fields="$(
ruby -e '
  text = File.read(ARGV.fetch(0))
  version = text[/^\s*version\s+"([^"]+)"/, 1]
  sha = text[/^\s*sha256\s+"([0-9a-f]{64})"/, 1]
  url = text[/^\s*url\s+"([^"]+)"/, 1]
  abort("Unable to parse version/sha256/url from #{ARGV[0]}") unless version && sha && url
  puts(version)
  puts(sha)
  puts(url)
' "$CASK_FILE"
)"

CASK_VERSION="$(printf '%s\n' "$cask_fields" | sed -n '1p')"
CASK_SHA="$(printf '%s\n' "$cask_fields" | sed -n '2p')"
CASK_URL_TEMPLATE="$(printf '%s\n' "$cask_fields" | sed -n '3p')"

if [[ "$CASK_VERSION" != "$VERSION" ]]; then
    echo "Version mismatch: cask=$CASK_VERSION expected=$VERSION" >&2
    exit 1
fi

RELEASE_URL="${CASK_URL_TEMPLATE//\#\{version\}/$VERSION}"
TMP_REMOTE_FILE="${TMPDIR:-/tmp}/quotabar-verify-${VERSION}-$$.dmg"

cleanup() {
    rm -f "$TMP_REMOTE_FILE"
}
trap cleanup EXIT

echo "Checking release asset SHA..."
echo "  URL: $RELEASE_URL"
curl -sSfL --retry 2 --retry-delay 1 -o "$TMP_REMOTE_FILE" "$RELEASE_URL"
REMOTE_SHA="$(shasum -a 256 "$TMP_REMOTE_FILE" | awk '{print $1}')"

if [[ "$REMOTE_SHA" != "$CASK_SHA" ]]; then
    echo "SHA mismatch detected:" >&2
    echo "  cask  : $CASK_SHA" >&2
    echo "  remote: $REMOTE_SHA" >&2
    exit 1
fi

echo "OK: cask SHA matches GitHub release asset."

if [[ "$SKIP_BREW" == true ]]; then
    echo "Skipped brew fetch verification (--skip-brew)."
    exit 0
fi

if ! command -v brew >/dev/null 2>&1; then
    echo "brew not found, skipping brew verification." >&2
    exit 0
fi

TOKEN="$TAP/$CASK_NAME"
echo "Running brew fetch verification for $TOKEN ..."
HOMEBREW_NO_AUTO_UPDATE=1 brew tap "$TAP" >/dev/null
TAP_REPO="$(brew --repository)/Library/Taps/${TAP%/*}/homebrew-${TAP#*/}"
if [[ -d "$TAP_REPO/.git" ]]; then
    git -C "$TAP_REPO" fetch origin >/dev/null 2>&1 || true
    if git -C "$TAP_REPO" show-ref --verify --quiet refs/remotes/origin/main; then
        git -C "$TAP_REPO" reset --hard origin/main >/dev/null
    elif git -C "$TAP_REPO" show-ref --verify --quiet refs/remotes/origin/master; then
        git -C "$TAP_REPO" reset --hard origin/master >/dev/null
    fi
fi
CACHE_PATH="$(brew --cache --cask "$TOKEN")"
rm -f "$CACHE_PATH"
HOMEBREW_NO_AUTO_UPDATE=1 brew fetch --cask --force "$TOKEN" >/dev/null

if [[ ! -f "$CACHE_PATH" ]]; then
    echo "brew fetch completed but cache file not found: $CACHE_PATH" >&2
    exit 1
fi

BREW_SHA="$(shasum -a 256 "$CACHE_PATH" | awk '{print $1}')"
if [[ "$BREW_SHA" != "$CASK_SHA" ]]; then
    echo "brew cache SHA mismatch:" >&2
    echo "  cask: $CASK_SHA" >&2
    echo "  brew: $BREW_SHA" >&2
    exit 1
fi

echo "OK: brew fetch checksum verification passed."
