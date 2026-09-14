{
  perSystem =
    { config, pkgs, ... }:
    {
      devShells.default = pkgs.mkShellNoCC {
        shellHook = config.pre-commit.shellHook;
        # The wrapped Nix, so `nix flake check` here loads the builtin too.
        packages = [
          config.packages.nix
          pkgs.deadnix
          pkgs.nixfmt-tree
          pkgs.rage
          pkgs.shellcheck
          pkgs.statix
        ];
      };
    };
}
