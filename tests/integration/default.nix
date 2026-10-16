{
  flake-parts,
  nixpkgs,
  self,
}:
let
  testContext = import ../test-context.nix { inherit flake-parts nixpkgs self; };
in
{
  flake-module = import ./flake-module.nix testContext;
  flake-outputs = import ./flake-outputs.nix testContext;
}
