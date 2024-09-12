{
  description = "Flake for building Cursor on Linux ARM and Windows ARM platforms";

  inputs = {
    # Pinned to align the version of VS Codium with Cursor's build.
    nixpkgs.url = "github:NixOS/nixpkgs/212defe037698e18fc9521dfe451779a8979844c";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "aarch64-linux" "armv7l-linux" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };

          # It's difficult to find pinned versions of Cursor.
          # The latest version and download URL were found here:
          # https://changelog.cursor.sh/
          cursorVersion = "0.40";
          # This is the VS Code version that Cursor was built on.
          vscodeVersion = "1.91.1";

          cursorSrc = pkgs.appimageTools.extractType2 {
            name = "cursor-appimage";
            src = pkgs.fetchurl {
              url = "https://dl.todesktop.com/230313mzl4w4u92/linux/appimage/x64";
              sha256 = "sha256-ZURE8UoLPw+Qo1e4xuwXgc+JSwGrgb/6nfIGXMacmSg=";
            };
          };
          vscodeLinuxArm64 = builtins.fetchTarball {
            url = "https://update.code.visualstudio.com/${vscodeVersion}/linux-arm64/stable";
            sha256 = "sha256:1rpd014rw7ccaq7vysdbf3crkmlb9gxdkdpvzghn1jcgvqd99880";
          };
          vscodeLinuxArm32 = builtins.fetchTarball {
            url = "https://update.code.visualstudio.com/${vscodeVersion}/linux-armhf/stable";
            sha256 = "sha256:0a5lygf6b7m8pj5h20dzif52radf41g3hazx4zhky370gq3xrgwd";
          };
          vscodeWindowsArm64 = pkgs.fetchzip {
            stripRoot = false;
            url = "https://update.code.visualstudio.com/${vscodeVersion}/win32-arm64-archive/stable#file.zip";
            sha256 = "sha256-2pAXxDyDOazfOndQzydQCzXXBHCwQ5tgrs4RyCqcslw=";
          };

          # Copies Cursor-specific resources into the VS Code package.
          copyCursorFiles = root: ''
            cp -R ${cursorSrc}/resources/app/out ${root}/resources/app/
            cp -R ${cursorSrc}/resources/app/*.json ${root}/resources/app/
            cp -R ${cursorSrc}/resources/app/extensions/cursor-* ${root}/resources/app/extensions/
            rm -rf "${root}/resources/app/node_modules"{,.asar}
            cp -R ${cursorSrc}/resources/app/node_modules.asar ${root}/resources/app/
            rm -rf ${root}/resources/app/resources
            cp -R ${cursorSrc}/resources/app/resources ${root}/resources/app/
          '';

          artifactName = os: arch: ext: "cursor_${cursorVersion}_${os}_${arch}.${ext}";

          # Overrides the VS Code package with Cursor's resources.
          buildCursorNix = { vscodePackage }:
            vscodePackage.overrideAttrs (oldAttrs: {
              pname = "cursor";
              version = cursorVersion;
              executableName = "cursor";

              postInstall = (oldAttrs.postInstall or "") + ''
                ${(copyCursorFiles "$out/lib/vscode")}

                # Replace VS Code's icon and desktop file with Cursor's
                cp ${cursorSrc}/cursor.png $out/share/pixmaps/cursor.png
                cp ${cursorSrc}/cursor.desktop $out/share/applications/cursor.desktop

                # Rename the binary
                mv $out/bin/code $out/bin/cursor || true
                mv $out/bin/codium $out/bin/cursor || true
              '';

              meta = oldAttrs.meta // {
                description = "Cursor ${cursorVersion}";
                mainProgram = "cursor";
              };
            });

          # Builds Cursor using a prepackaged set of VS Code files.
          # This is for creating dynamically linked builds.
          buildCursorPrepackaged = { vscodeFiles, name, isWindows ? false }:
            pkgs.stdenv.mkDerivation {
              pname = "cursor-${name}";
              version = cursorVersion;
              src = vscodeFiles;
              dontPatchShebangs = true;
              buildPhase = ''
                cp -R --preserve=mode,timestamps . $out

                ${copyCursorFiles "$out"}

                # Replace VS Code's icon and desktop file with Cursor's
                cp ${cursorSrc}/cursor.png $out/cursor.png
                cp ${cursorSrc}/cursor.desktop $out/cursor.desktop
                cp -R ${cursorSrc}/resources/todesktop* $out/resources/
                
                # This is excluded intentionally. It causes an error in console,
                # but there's some token we must be missing?
                # cp ${cursorSrc}/resources/app-update.yml $out/resources/

                # Cursor doesn't have a root bin dir
                rm -rf $out/bin

                mv $out/code $out/cursor || true
                mv $out/codium $out/cursor || true
                mv $out/Code.exe $out/Cursor.exe || true

                # Platform-specific adjustments
                ${if !isWindows then ''
                  cp -R ${cursorSrc}/usr $out
                  cp ${cursorSrc}/AppRun $out
                  cp ${cursorSrc}/.DirIcon $out
                '' else ''
                ''}
              '';
            };
        in
        {
          extract-vscode-version = pkgs.runCommand "extract-vscode-version" { } ''
            ${pkgs.jq}/bin/jq -r .vscodeVersion ${cursorSrc}/resources/app/product.json >> $out
          '';

          cursor = {
            linux = {
              arm64 = buildCursorPrepackaged {
                vscodeFiles = vscodeLinuxArm64;
                name = "linux-arm64";
              };
              arm64-appimage = pkgs.stdenv.mkDerivation {
                name = artifactName "linux" "arm64" "AppImage";
                src = self.packages.${system}.cursor.linux.arm64;
                dontPatchShebangs = true;
                buildInputs = [ pkgs.appimagekit ];
                buildPhase = ''
                  mkdir -p $out
                  ARCH=arm_aarch64 appimagetool $src $out/${artifactName "linux" "arm64" "AppImage"}
                  chmod +x $out/${artifactName "linux" "arm64" "AppImage"}
                  patchelf --set-interpreter /lib/ld-linux-aarch64.so.1 $out/${artifactName "linux" "arm64" "AppImage"}
                '';
              };
              arm64-targz = pkgs.runCommand "tarball" { } ''
                mkdir -p $out
                cd ${self.packages.${system}.cursor.linux.arm64}
                ${pkgs.gnutar}/bin/tar -czvf $out/${artifactName "linux" "arm64" "tar.gz"} .
              '';

              arm32 = buildCursorPrepackaged {
                vscodeFiles = vscodeLinuxArm32;
                name = "linux-arm32";
              };
              arm32-appimage = pkgs.stdenv.mkDerivation {
                name = artifactName "linux" "arm32" "AppImage";
                src = self.packages.${system}.cursor.linux.arm32;
                dontPatchShebangs = true;
                buildInputs = [ pkgs.appimagekit ];
                buildPhase = ''
                  mkdir -p $out
                  ARCH=arm appimagetool $src $out/${artifactName "linux" "arm32" "AppImage"}
                  chmod +x $out/${artifactName "linux" "arm32" "AppImage"}
                  patchelf --set-interpreter /lib/ld-linux.so.3 $out/${artifactName "linux" "arm32" "AppImage"}
                '';
              };
              arm32-targz = pkgs.runCommand "tarball" { } ''
                mkdir -p $out
                cd ${self.packages.${system}.cursor.linux.arm32}
                ${pkgs.gnutar}/bin/tar -czvf $out/${artifactName "linux" "arm32" "tar.gz"} .
              '';
            };
            windows = {
              arm64 = buildCursorPrepackaged {
                vscodeFiles = vscodeWindowsArm64;
                name = "windows-arm64";
                isWindows = true;
              };
              arm64-zip = pkgs.runCommand "zip" { } ''
                mkdir -p $out
                cd ${self.packages.${system}.cursor.windows.arm64}
                ${pkgs.zip}/bin/zip -r $out/${artifactName "windows" "arm64" "zip"} .
              '';
            };

            nix = buildCursorNix {
              vscodePackage = pkgs.vscodium;
            };
          };

          default = self.packages.${system}.cursor.nix;
        }
      );
    };
}
