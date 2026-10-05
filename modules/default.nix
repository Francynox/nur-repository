{
  # Add your NixOS modules here
  #
  # my-module = ./my-module;
  kea = import ./pkgs/kea.nix;
  bind = import ./pkgs/bind.nix;
  adguardhome = import ./pkgs/adguardhome.nix;
  unbound = import ./pkgs/unbound.nix;
  sparkyfitness = import ./pkgs/sparkyfitness.nix;
  growpart = import ./growpart.nix;
  mutable-configs = import ./mutable-configs.nix;
  telegram-notify = import ./telegram-notify.nix;
  lxc-wipe-on-boot = import ./lxc-wipe-on-boot;
  deploy-user = import ./deploy-user.nix;
  auto-update = import ./auto-update;
}
