# Grok Bot (xAI) Linux client — standalone, publishable package flake
#
# Linux builds are published at https://x.ai/bot#download: a .deb, .rpm and
# .AppImage, served from xAI's downloads CDN. Versioned, per-release download
# URLs plus hashes are pinned in sources.json (queried from xAI's download
# API, which reports the current stable version and all artifact URLs for
# linux-x64 and linux-arm64).
#
# Refresh pins with ./update-package.sh (run from the repo root, or
# `nix run .#update` there). CI runs the same script daily and pushes the
# bump — see .github/workflows/update.yml.
#
# NOTE: the artifact URLs shown on the download page (api2.cursor.sh/.../
# grok-bot-<build-id>) are NOT per-release: xAI re-points them to new builds
# in place (observed 0.70.2 -> 0.77.0 at unchanged URLs). sources.json pins
# the API-provided versioned URLs instead, which are stable.
#
# Builder patterns follow nixpkgs conventions (e.g. nixpkgs#obsidian for
# deb, nixpkgs#github-copilot-app packaging style for AppImage).
{
  description = "Grok Bot desktop client by xAI (Linux packaging)";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];

      # Standalone flake: unfree allowed here because Grok Bot ships as
      # binary-only, unfree redistributables from xAI.
      pkgsFor = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      sources = builtins.fromJSON (builtins.readFile ./sources.json);
      version = sources.version;

      makePackages = system:
        let
          pkgs = pkgsFor system;
          inherit (pkgs) lib;
          artifacts = sources.sources.${system} or { };

          baseMeta = {
            description = "Grok Bot desktop client by xAI";
            homepage = "https://x.ai/bot";
            license = lib.licenses.unfree;
            mainProgram = "grok-bot";
            platforms = [ system ];
            sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
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

          commonAttrs = {
            pname = "grok-bot";
            inherit version;
            meta = baseMeta;
          };

          # .deb: extract with dpkg-deb, flatten /usr, auto-patch ELF binaries.
          # Upstream desktop entry uses Exec=grok-bot, so expose the app binary
          # under bin/ (which is on PATH) for launcher compatibility.
          mkDeb = src: pkgs.stdenv.mkDerivation (commonAttrs // {
            inherit src;
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
          mkRpm = src: pkgs.stdenv.mkDerivation (commonAttrs // {
            inherit src;
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
          mkAppImage = src: pkgs.appimageTools.wrapType2 (commonAttrs // {
            inherit src;
            extraPkgs = pkgs': with pkgs'; [ pkgs'.libsecret ];
          });

          # Evaluable placeholder: `nix build` fails with a clear message,
          # evaluation (and `nix flake check`) succeeds.
          mkPlaceholder = system: what:
            pkgs.runCommand "grok-bot-placeholder" {
              meta = baseMeta // {
                description = "Placeholder — no ${what} artifact pinned for ${system}";
              };
            } ''
              echo "grok-bot: no ${what} artifact pinned for ${system}." >&2
              echo "Run ./update-package.sh (or extend the pin scope in it)" >&2
              echo "to add it to sources.json." >&2
              exit 1
            '';

          maybeBuild = format: builder:
            let src = artifacts.${format} or null; in
            if src != null
            then builder (pkgs.fetchurl { inherit (src) url hash; })
            else mkPlaceholder system format;

          pkgSet = {
            grok-bot = maybeBuild "deb" mkDeb;
            grok-bot-rpm = maybeBuild "rpm" mkRpm;
            grok-bot-appimage = maybeBuild "appimage" mkAppImage;
          };
        in
        pkgSet // { default = pkgSet.grok-bot; };
    in
    {
      packages = nixpkgs.lib.genAttrs systems makePackages;

      lib.hasArtifact = system: format:
        (sources.sources.${system} or { }) ? ${format};

      # Re-pin helper: runs ./update-package.sh against the current working
      # tree. Run `nix run .#update` from the repo root.
      apps = nixpkgs.lib.genAttrs systems (system:
        let pkgs = pkgsFor system; in
        {
          update = {
            type = "app";
            program = toString (pkgs.writeShellScript "grok-bot-update" ''
              export PATH="${pkgs.lib.makeBinPath [ pkgs.curl pkgs.jq pkgs.nix ]}:$PATH"
              exec ${pkgs.bash}/bin/bash ${./update-package.sh} "$@"
            '');
          };
        });
    };
}
