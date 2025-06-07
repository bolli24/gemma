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
    wayland-scanner
    pulseaudioFull
    unzip
    libxkbcommon
    glfw
  ];
}
