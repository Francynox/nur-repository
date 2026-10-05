# This file describes your repository contents.
# It should return a set of nix derivations
# and optionally the special attributes `lib`, `modules` and `overlays`.
# It should NOT import <nixpkgs>. Instead, you should take pkgs as an argument.
# Having pkgs default to <nixpkgs> is fine though, and it lets you use short
# commands such as:
#     nix-build -A mypackage
{
  pkgs ? import <nixpkgs> { },
}:
{
  # The `lib`, `modules`, and `overlays` names are special
  lib = import ./lib { inherit pkgs; }; # functions
  modules = import ./modules; # NixOS modules
  overlays = import ./overlays; # nixpkgs overlays

  kea = pkgs.callPackage ./pkgs/kea { };
  bind = pkgs.callPackage ./pkgs/bind { };
  adguardhome = pkgs.callPackage ./pkgs/adguardhome { };
  unbound = pkgs.callPackage ./pkgs/unbound { };
  proxmox-vma = pkgs.callPackage ./pkgs/proxmox-vma { };
  sparkyfitness-server = pkgs.callPackage ./pkgs/sparkyfitness/server.nix { };
  sparkyfitness-frontend = pkgs.callPackage ./pkgs/sparkyfitness/frontend.nix { };
  # some-qt5-package = pkgs.libsForQt5.callPackage ./pkgs/some-qt5-package { };
  # ...
}
