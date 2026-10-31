{ inputs, self, ... }:
{
  imports = [
    inputs.nix-unit.modules.flake.default
    inputs.treefmt-nix.flakeModule
  ];

  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    {
      treefmt.imports = [ ./treefmt.nix ];
      devShells.default = pkgs.callPackage ./shell.nix {
        packages = self.packages.${system};
        treefmtShell = config.treefmt.build.devShell;
      };
      checks = import ./checks.nix {
        inherit inputs pkgs;
        packages = self.packages.${system};
      };
      nix-unit = {
        package = pkgs.nix-unit;
        inputs = removeAttrs inputs [ "self" ];
        enableSystemAgnostic = false;
        tests = {
          unit = import ../tests/unit {
            inherit pkgs;
            inherit (inputs) nixpkgs;
          };
          integration = import ../tests/integration { inherit (inputs) flake-parts nixpkgs self; };
        };
      };
    };
}
