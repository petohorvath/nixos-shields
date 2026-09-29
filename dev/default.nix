{ inputs, self, ... }:
{
  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    {
      formatter = pkgs.callPackage ./formatter.nix { };
      devShells.default = pkgs.callPackage ./shell.nix {
        inherit (config) formatter;
        packages = self.packages.${system};
      };
      checks = import ./checks.nix {
        inherit inputs pkgs;
        inherit (config) formatter;
        packages = self.packages.${system};
      };
    };
}
