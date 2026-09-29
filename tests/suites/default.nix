{ testContext }:
{
  flakeModule = import ./flake-module.nix testContext;
  nixosModule = import ./nixos-module.nix testContext;
}
