#!/usr/bin/env bash
# Re-pin Grok Bot artifacts into sources.json.
#
# Asks the download API for the current stable release (version + artifact
# URLs for linux-x64 and linux-arm64), refuses non-matching pairs, prefetches
# every pinned artifact, rewrites sources.json, and build-tests the packages.
#
# Run from the repo root (or `nix run .#update` there). Does not commit —
# review the diff yourself, or let CI commit it.
#
# NOTE: the download page's URLs (api2.cursor.sh/.../grok-bot-<build-id>) are
# re-pointed in place by upstream; the API's versioned URLs are the reliable
# ones and are what this script pins.
set -euo pipefail

API_BASE="https://api2.cursor.sh/updates/api/download/stable"
SOURCES_FILE="sources.json"

die() { echo "error: $*" >&2; exit 1; }

for tool in curl jq nix; do
  command -v "$tool" >/dev/null 2>&1 || die "missing tool: $tool"
done
[ -f "$SOURCES_FILE" ] || die "run from the repo root ($SOURCES_FILE not found)"

# Pin scope: which artifact formats are pinned per Nix system. Extend here
# (e.g. add rpm/appimage for aarch64) and in makePackages if ever needed.
pin_formats() {
  case "$1" in
    x86_64-linux) echo "deb rpm appimage" ;;
    aarch64-linux) echo "deb" ;;
    *) die "unsupported system: $1" ;;
  esac
}

api_platform() {
  case "$1" in
    x86_64-linux) echo "linux-x64" ;;
    aarch64-linux) echo "linux-arm64" ;;
    *) die "unsupported system: $1" ;;
  esac
}

# API JSON field carrying the artifact URL, per format.
api_field() {
  case "$1" in
    deb) echo "debUrl" ;;
    rpm) echo "rpmUrl" ;;
    appimage) echo "downloadUrl" ;;
    *) die "unknown format: $1" ;;
  esac
}

nix_system() { echo "$(uname -m)-linux"; }

meta_for() {
  case "$1" in
    x86_64-linux) echo "$meta_x64" ;;
    aarch64-linux) echo "$meta_arm64" ;;
    *) die "unsupported system: $1" ;;
  esac
}

fetch_meta() {
  local platform="$1"
  curl -fsSL "$API_BASE/$platform/sand" || die "download API unreachable ($platform)"
}

meta_x64=$(fetch_meta linux-x64)
meta_arm64=$(fetch_meta linux-arm64)

new_version=$(jq -r '.version // empty' <<<"$meta_x64")
[ -n "$new_version" ] || die "API returned no version for linux-x64"
arm_version=$(jq -r '.version // empty' <<<"$meta_arm64")
[ "$new_version" = "$arm_version" ] ||
  die "release pair mismatch (linux-x64=$new_version, linux-arm64=$arm_version); refusing to pin a partial release"

old_version=$(jq -r '.version' "$SOURCES_FILE")
if [ "$new_version" = "$old_version" ]; then
  echo "Already pinned to $old_version — nothing to do."
  exit 0
fi

echo "Re-pinning Grok Bot: $old_version -> $new_version"

out=$(jq -n --arg v "$new_version" '{version: $v, sources: {}}')
for sys in x86_64-linux aarch64-linux; do
  meta=$(meta_for "$sys")
  for format in $(pin_formats "$sys"); do
    field=$(api_field "$format")
    url=$(jq -r --arg f "$field" '.[$f] // empty' <<<"$meta")
    [ -n "$url" ] || die "API returned no $field for $sys"
    # The API URLs embed the release version; anything else is unexpected.
    [[ "$url" == *"$new_version"* ]] ||
      echo "warning: $field for $sys does not embed $new_version: $url" >&2

    echo "Prefetching $sys/$format: $url"
    hash=$(nix store prefetch-file --json --hash-type sha256 "$url" | jq -r '.hash')

    entry=$(jq -n --arg url "$url" --arg hash "$hash" '{url: $url, hash: $hash}')
    out=$(jq --arg s "$sys" --arg f "$format" --argjson e "$entry" \
      '.sources[$s][$f] = $e' <<<"$out")
  done
done

jq . <<<"$out" > "$SOURCES_FILE"
echo "Wrote $SOURCES_FILE"

echo "Build-testing packages for $(nix_system)..."
for format in $(pin_formats "$(nix_system)"); do
  case "$format" in
    deb) pkg=grok-bot ;;
    *) pkg="grok-bot-$format" ;;
  esac
  nix build ".#$pkg" --no-link --print-out-paths
done

echo
echo "Done. Review the diff before committing:"
echo "  git diff $SOURCES_FILE"
