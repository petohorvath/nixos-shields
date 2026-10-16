{ inputs, self, ... }:
{
  imports = [ inputs.nix-unit.modules.flake.default ];

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
      };
      nix-unit = {
        package = pkgs.nix-unit;
        inputs = removeAttrs inputs [ "self" ];
        tests = {
          unit = import ../tests/unit {
            inherit (inputs) nixpkgs;
            inherit system;
          };
          integration = import ../tests/integration {
            inherit (inputs) flake-parts nixpkgs self;
            inherit system;
          };
        };
      };
    };
}
