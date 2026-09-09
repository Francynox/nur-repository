{ inputs, ... }:
{
  perSystem =
    {
      config,
      pkgs,
      system,
      lib,
      ...
    }:
    let
      nur = import ./default.nix { inherit pkgs; };

      tests = import ./tests {
        inherit pkgs;
        modules = lib.attrValues nur.modules;
      };

      isSupported =
        p:
        lib.isDerivation p && lib.meta.availableOn pkgs.stdenv.hostPlatform p && !(p.meta.broken or false);

      isFree = p: lib.all (l: l.free or true) (lib.toList (p.meta.license or [ ]));

      isBuildable = p: isSupported p && !(p.preferLocalBuild or false);

      isCacheable = p: isBuildable p && isFree p;

      mkCi =
        condition:
        let
          selectedPkgs = lib.filterAttrs (_: condition) nur;

          selectedTests = lib.filterAttrs (n: _: !(nur ? ${n}) || condition nur.${n}) tests;

          prefixAttrs = prefix: set: lib.mapAttrs' (n: v: lib.nameValuePair "${prefix}-${n}" v) set;
        in
        (prefixAttrs "pkg" selectedPkgs) // (prefixAttrs "check" selectedTests);
    in
    {
      options.ciJobs = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };

      config = {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [
            (import ./overlays/francynox-namespace.nix)
          ];
          config.allowUnfree = true;
        };

        treefmt = {
          projectRootFile = "flake.nix";
          programs.yamlfmt.enable = true;
          programs.jsonfmt.enable = true;
          programs.just.enable = true;
          programs.nixfmt.enable = true;
          programs.deadnix.enable = true;
          programs.statix.enable = true;
          programs.ruff = {
            check = true;
            format = true;
          };
        };

        pre-commit = {
          check.enable = true;
          settings.hooks.treefmt.enable = true;
          settings.hooks.zizmor.enable = true;
          settings.hooks.actionlint.enable = true;
          settings.hooks.nix-flake-check = {
            enable = true;
            name = "nix-flake-check";
            entry = "bash -c 'if command -v nix >/dev/null; then nix flake check; else echo \"Skipping nix flake check in sandbox\"; fi'";
            language = "system";
            pass_filenames = false;
          };
        };

        legacyPackages = nur;
        packages = lib.filterAttrs (_: isSupported) nur;
        checks = mkCi isSupported;
        ciJobs = mkCi isCacheable;

        devShells.default = pkgs.mkShell {
          shellHook = ''
            ${config.pre-commit.installationScript}
          '';
          packages = [
            config.treefmt.build.wrapper
            pkgs.nix-update
            pkgs.deadnix
            pkgs.statix
            pkgs.ruff
            pkgs.zizmor
            pkgs.actionlint
          ];
        };
      };
    };
}
