{
  flake-parts,
  nixpkgs,
  self,
  system,
}:
let
  testContext = import ../test-context.nix {
    inherit
      flake-parts
      nixpkgs
      self
      system
      ;
  };
in
{
  flake-module = import ./flake-module.nix testContext;
  flake-outputs = import ./flake-outputs.nix testContext;
}
