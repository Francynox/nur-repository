{
  pkgs,
  modules,
  ...
}:
{
  kea = import ./kea.nix { inherit pkgs modules; };
  bind = import ./bind.nix { inherit pkgs modules; };
  adguardhome = import ./adguardhome.nix { inherit pkgs modules; };
  unbound = import ./unbound.nix { inherit pkgs modules; };
  auto-update-push = import ./auto-update-push.nix { inherit pkgs modules; };
  auto-update-pull = import ./auto-update-pull.nix { inherit pkgs modules; };
  growpart = import ./growpart.nix { inherit pkgs modules; };
  mutable-configs = import ./mutable-configs.nix { inherit pkgs modules; };
  telegram-notify = import ./telegram-notify.nix { inherit pkgs modules; };
  lxc-wipe-on-boot = import ./lxc-wipe-on-boot.nix { inherit pkgs modules; };
  deploy-user = import ./deploy-user.nix { inherit pkgs modules; };
}
