let
  unstable = import (fetchTarball https://nixos.org/channels/nixos-unstable/nixexprs.tar.xz) {};
in
  {pkgs ? import <nixpkgs> {}}:
    pkgs.mkShell {
      nativeBuildInputs = with pkgs.buildPackages; [
        zig
        SDL2
        pkg-config
        xorg.libX11
        xorg.libXcursor
        xorg.libXrandr
        xorg.libXinerama
        xorg.libXi
        xorg.libXext
        xorg.libXfixes
        wayland
        pulseaudioFull
        unzip
        libxkbcommon
        glfw
      ];
    }
