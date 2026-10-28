# grok-bot-nix

Nix packaging for the [Grok Bot](https://x.ai/bot) desktop client by xAI on
Linux. Ships the official artifacts — `.deb`, `.rpm`, and `.AppImage` — as
Nix packages for `x86_64-linux` (all formats) and `aarch64-linux` (deb).

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
  inputs.grok-bot.packages.${pkgs.system}.grok-bot        # .deb (recommended)
  # inputs.grok-bot.packages.${pkgs.system}.grok-bot-rpm
  # inputs.grok-bot.packages.${pkgs.system}.grok-bot-appimage
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

| Package             | Source    | x86_64-linux | aarch64-linux |
|---------------------|-----------|--------------|---------------|
| `grok-bot`          | .deb      | yes          | yes           |
| `grok-bot-rpm`      | .rpm      | yes          | —             |
| `grok-bot-appimage` | .AppImage | yes          | —             |

The deb/rpm builds extract the official packages and patch the ELF binaries
against store libraries (no FHS sandbox at runtime); the AppImage is wrapped
with `appimageTools`.

## Updating

Artifact pins live in `sources.json` as versioned, per-release URLs (queried
from the download API) plus sha256 hashes. A scheduled GitHub Action runs
`./update-package.sh` daily: when a new stable release ships, it re-pins all
artifacts, build-tests them, and pushes the bump. Nothing to do on your side.

Manual refresh:

```bash
./update-package.sh    # from the repo root (or: nix run .#update)
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for details and troubleshooting.
