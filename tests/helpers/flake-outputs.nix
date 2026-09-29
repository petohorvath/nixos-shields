# The public flake outputs, assembled with the supplied inputs so the
# tests exercise exactly what consumers import.
{ flakeParts, nixpkgs }:
let
  inputs = {
    flake-parts = flakeParts;
    inherit nixpkgs;
  };
  self = (import ../../flake.nix).outputs (inputs // { inherit self; }) // {
    outPath = ../..;
    inherit inputs;
  };
in
self
