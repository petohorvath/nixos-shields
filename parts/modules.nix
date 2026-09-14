{
  flake.nixosModules.default = import ../modules/nixos.nix;
  flake.flakeModule = import ../modules/flake.nix;
}
