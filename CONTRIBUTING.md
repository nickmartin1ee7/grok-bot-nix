# Contributing

Pins refresh automatically (a scheduled workflow runs `./update-package.sh`
daily, build-tests, and pushes). Manual work is usually only needed when CI
fails or the API is unreachable.

## How pinning works

- `sources.json` holds `version` plus `{url, hash}` per artifact and system.
  URLs are the API's versioned, per-release links (stable, unlike the
  re-pointed slugs shown on the download page).
- `./update-package.sh` queries the download API
  (`https://api2.cursor.sh/updates/api/download/stable/<platform>/sand` —
  `linux-x64` / `linux-arm64`), refuses releases where the two platforms
  disagree on `version`, prefetches every pinned artifact, rewrites
  `sources.json`, and runs `nix build` for the current system's packages.
- Pin scope (which formats exist per system) is declared in two places that
  must stay in sync: `pin_formats` in `update-package.sh` and the artifact
  lookups in `flake.nix` (`makePackages`).

## Manual refresh

```bash
./update-package.sh    # or: nix run .#update
git diff sources.json  # review
git commit -m "Re-pin artifacts to <version>" && git push
```

If the API is down, grab the URLs from https://x.ai/bot#download by hand and
prefetch them:

```bash
nix store prefetch-file <url> --json   # prints the hash for sources.json
```

Verify artifact versions when pinning by hand:

```bash
nix run nixpkgs#dpkg -- -f /nix/store/<prefetched-deb> Package Version
nix run nixpkgs#rpm -- -qp --qf '%{VERSION}\n' /nix/store/<prefetched-rpm>
```

## Hash mismatch in a fixed-output derivation

Usually means upstream moved to a newer release before CI re-pinned (or the
pin predates a release). Run the manual refresh above; the error's `got:`
hash should match what prefetching reports.

## Packaging changes

If you touch the builders, follow nixpkgs conventions (see `nixpkgs#obsidian`
for deb packaging, `nixpkgs#github-copilot-app` for AppImage) and run:

```bash
nix build .#grok-bot .#grok-bot-rpm .#grok-bot-appimage --no-link
nix flake check
```
