# Grok Bot (xAI) Linux client — standalone, publishable package flake
#
# Linux builds are published at https://x.ai/bot#download ("Download on
# Linux"): a .deb, .rpm and .AppImage, all served from xAI's downloads CDN.
# Each release URL embeds a per-release build ID, e.g.
#   https://api2.cursor.sh/updates/download/stable/linux-x64/grok-bot-fb0a830618be0c54
# NOTE: xAI re-points the SAME URLs to new builds on later releases (observed
# 0.70.2 -> 0.77.0 at unchanged URLs), so stale-hash failures are expected
# after upstream releases. After every release, re-prefetch at the same URLs
# and bump version + hashes: `nix store prefetch-file <url> --json`.
# Builder patterns follow nixpkgs conventions (e.g. nixpkgs#obsidian for
# deb, nixpkgs#github-copilot-app packaging style for AppImage).
{
  description = "Grok Bot desktop client by xAI (Linux packaging)";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      # Standalone flake: unfree allowed here because Grok Bot ships as
      # binary-only, unfree redistributables from xAI.
      pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };

      artifacts = {
        deb = {
          version = "0.77.0";
          url = "https://api2.cursor.sh/updates/download/stable/linux-x64/grok-bot-fb0a830618be0c54";
          hash = "sha256-t08SXmrfOiXSlu+ZpKAEerSxevv8jp/dqg5XHc7+Qzw=";
        };
        rpm = {
          version = "0.77.0";
          # .rpm from x.ai/bot#download → "More downloads" (rpm, x86_64)
          url = "https://api2.cursor.sh/updates/download/stable/linux-x64/grok-bot-cc18e4e726507b90";
          hash = "sha256-s+Zvme12TPUJLSqPu2lIxC9Qq/sSjF4wttDfAjMjj9I=";
        };
        appimage = {
          version = "0.77.0";
          url = "https://api2.cursor.sh/updates/download/stable/linux-x64/grok-bot-6f47c900083d6a0c";
          hash = "sha256-bRFbuv9M9mlvA1T5sOAj/aa/6pwtMmy1Wd9gpgBaJVc=";
        };
      };

      baseMeta = {
        description = "Grok Bot desktop client by xAI";
        homepage = "https://x.ai/bot";
        license = pkgs.lib.licenses.unfree;
        mainProgram = "grok-bot";
        platforms = [ system ];
        sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
      };

      fetchArtifact = artifact: pkgs.fetchurl {
        inherit (artifact) url hash;
      };

      runtimeLibs = with pkgs; [
        stdenv.cc.cc.lib
        alsa-lib
        atk
        at-spi2-atk
        cairo
        cups
        dbus
        expat
        fontconfig
        freetype
        gdk-pixbuf
        glib
        gtk3
        libdrm
        mesa
        nspr
        nss
        pango
        systemd
        libx11
        libxcomposite
        libxdamage
        libxext
        libxfixes
        libxi
        libxrandr
        libxrender
        libxscrnsaver
        libxtst
        libxkbcommon
        libsecret
        libnotify
        libappindicator-gtk3
        libuuid
        util-linux
        xdg-utils
      ];

      commonAttrs = artifact: {
        pname = "grok-bot";
        version = artifact.version;
        meta = baseMeta;
      };

      # .deb: extract with dpkg-deb, flatten /usr, auto-patch ELF binaries.
      # Upstream desktop entry uses Exec=grok-bot, so expose the app binary
      # under bin/ (which is on PATH) for launcher compatibility.
      mkDeb = artifact:
        pkgs.stdenv.mkDerivation (commonAttrs artifact // {
          src = fetchArtifact artifact;
          dontUnpack = true;
          dontConfigure = true;
          dontBuild = true;
          nativeBuildInputs = with pkgs; [ dpkg autoPatchelfHook ];
          buildInputs = runtimeLibs;
          installPhase = ''
            runHook preInstall
            dpkg-deb -x $src $out
            if [ -d "$out/usr" ]; then
              cp -a $out/usr/. $out/
              rm -rf $out/usr
            fi
            mkdir -p $out/bin
            ln -s "$out/opt/Grok Bot/grok-bot" $out/bin/grok-bot
            runHook postInstall
          '';
        });

      # .rpm: extract with rpmextract, flatten /usr, auto-patch ELF binaries
      mkRpm = artifact:
        pkgs.stdenv.mkDerivation (commonAttrs artifact // {
          src = fetchArtifact artifact;
          dontUnpack = true;
          dontConfigure = true;
          dontBuild = true;
          nativeBuildInputs = with pkgs; [ rpmextract autoPatchelfHook ];
          buildInputs = runtimeLibs;
          installPhase = ''
            runHook preInstall
            mkdir -p $TMPDIR/rpm
            cd $TMPDIR/rpm
            rpmextract $src
            cp -a $TMPDIR/rpm/. $out/
            if [ -d "$out/usr" ]; then
              cp -a $out/usr/. $out/
              rm -rf $out/usr
            fi
            # rpm debuginfo symlinks under lib/.build-id point at the
            # absolute /opt path; they dangle in the store. Drop them
            # before autoPatchelfHook's noBrokenSymlinks check.
            rm -rf "$out/lib/.build-id"
            # Mirror mkDeb: upstream desktop entry uses Exec=grok-bot,
            # so expose the app binary under bin/ (which is on PATH).
            mkdir -p $out/bin
            ln -s "$out/opt/Grok Bot/grok-bot" $out/bin/grok-bot
            runHook postInstall
          '';
        });

      # .AppImage: wrap with appimageTools (FHS-style runtime)
      mkAppImage = artifact:
        pkgs.appimageTools.wrapType2 (commonAttrs artifact // {
          src = fetchArtifact artifact;
          extraPkgs = pkgs': with pkgs'; [ pkgs'.libsecret ];
        });

      # Evaluable placeholder: `nix build` fails with a clear message,
      # evaluation (and `nix flake check`) succeeds.
      mkPlaceholder = what:
        pkgs.runCommand "grok-bot-placeholder" {
          meta = baseMeta // {
            description = "Placeholder — no ${what} artifact configured for Grok Bot";
          };
        } ''
          echo "grok-bot: no ${what} artifact configured." >&2
          echo "Grab Linux download links from https://x.ai/bot#download" >&2
          echo "and set 'artifacts.${what}' in this flake.nix." >&2
          exit 1
        '';

      maybeBuild = format: builder:
        if artifacts.${format} != null then builder artifacts.${format}
        else mkPlaceholder format;
    in
    {
      lib.hasArtifact = format: artifacts.${format} != null;

      packages.${system} = {
        grok-bot = maybeBuild "deb" mkDeb;
        grok-bot-rpm = maybeBuild "rpm" mkRpm;
        grok-bot-appimage = maybeBuild "appimage" mkAppImage;
        default = self.packages.${system}.grok-bot;
      };

      # Helper: `nix run .#update -- <version>` prints the CDN URLs for the
      # current release's build IDs (parse them from the x.ai/bot page with:
      #   curl -sL https://x.ai/bot | grep -oE 'https://api2[^"]+linux[^"]*'
      # ) so the artifact URLs/hashes can be re-pinned.
      apps.${system}.update = {
        type = "app";
        program = pkgs.lib.getExe (pkgs.writeShellScriptBin "grok-bot-update-urls" ''
          set -euo pipefail
          curl -sL https://x.ai/bot \
            | grep -oE 'https://api2[^"]+linux[^"]*' \
            | sort -u
        '');
      };
    };
}
