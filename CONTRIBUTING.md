# Contributing

Short version: bump the pins in `flake.nix`, build all three packages, commit,
push. That's the whole workflow — the packaging rarely changes, the artifacts
do.

## Why re-pinning is constant maintenance

xAI serves the Linux builds from URLs like

```
https://api2.cursor.sh/updates/download/stable/linux-x64/grok-bot-fb0a830618be0c54
```

but **re-uses the same URLs across releases** (observed 0.70.2 → 0.77.0 at
unchanged URLs). Every upstream release therefore invalidates the pinned
hashes until someone re-pins them.

## Re-pin recipe

1. **Prefetch the three artifacts** and note the new hashes:

   ```bash
   nix store prefetch-file https://api2.cursor.sh/updates/download/stable/linux-x64/grok-bot-fb0a830618be0c54 --json
   nix store prefetch-file https://api2.cursor.sh/updates/download/stable/linux-x64/grok-bot-cc18e4e726507b90 --json
   nix store prefetch-file https://api2.cursor.sh/updates/download/stable/linux-x64/grok-bot-6f47c900083d6a0c --json
   ```

   If those URLs 404 (rare), scrape the fresh build IDs from the download
   page with the helper app:

   ```bash
   nix run .#update    # prints the current CDN URLs from https://x.ai/bot
   ```

2. **Verify the new version** and bump `artifacts.<deb|rpm|appimage>.version`
   too (not just the hash):

   ```bash
   nix run nixpkgs#dpkg -- -f /nix/store/<prefetched-deb> Package Version
   nix run nixpkgs#rpm -- -qp --qf '%{VERSION}\n' /nix/store/<prefetched-rpm>
   ```

3. **Update** `version` + `hash` for all three artifacts in `flake.nix`.

4. **Build-test all three** before committing:

   ```bash
   nix build .#grok-bot .#grok-bot-rpm .#grok-bot-appimage --no-link
   ```

5. **Commit & push** with a message like `Re-pin artifacts to <version>`,
   including a one-line note on how the hashes were obtained.

## Packaging changes

If you touch the builders themselves, follow nixpkgs conventions
(see `nixpkgs#obsidian` for deb packaging, `nixpkgs#github-copilot-app` for
AppImage). Run all three builds as above, and `nix flake check` for a
no-artifact eval sanity check.
