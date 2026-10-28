# grok-bot-nix

Nix packaging for the [Grok Bot](https://x.ai/bot) desktop client by xAI on
Linux (x86_64). Ships three artifacts from xAI's CDN as a `.deb`, `.rpm`, and
`.AppImage`.

> **License**: unfree — binary-only redistributables from xAI. Set
> `nixpkgs.config.allowUnfree = true` (handled by this flake internally).

## Usage

Add the flake as an input and install a package:

```nix
# flake.nix
inputs.grok-bot = {
  url = "github:nickmartin1ee7/grok-bot-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

```nix
# NixOS / Home Manager
environment.systemPackages = [
  inputs.grok-bot.packages.x86_64-linux.grok-bot        # .deb (recommended)
  # inputs.grok-bot.packages.x86_64-linux.grok-bot-rpm
  # inputs.grok-bot.packages.x86_64-linux.grok-bot-appimage
];
```

For a NixOS integration example, see
[nickmartin1ee7/nixos-configuration](https://github.com/nickmartin1ee7/nixos-configuration)
(`modules/programs/grok-bot.nix`).

Or try it without installing:

```bash
nix run github:nickmartin1ee7/grok-bot-nix
```

## Packages

| Package             | Source   | Notes                                    |
|---------------------|----------|------------------------------------------|
| `grok-bot`          | .deb     | default; auto-patched ELF binaries       |
| `grok-bot-rpm`      | .rpm     | same as deb, extracted with rpmextract   |
| `grok-bot-appimage` | .AppImage| wrapped with `appimageTools` (FHS env)   |

## Important: artifacts are mutable

xAI **re-points the same CDN URLs to new builds on every release**, so pinned
hashes go stale and builds fail with `hash mismatch in fixed-output derivation`
after each upstream release. Re-pinning is expected maintenance — see
[CONTRIBUTING.md](CONTRIBUTING.md).
