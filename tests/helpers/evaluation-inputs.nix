/*
  Reconstruct development inputs from store paths for offline test
  evaluation. flake-parts has no default.nix, so its flake outputs are
  called directly with the reconstructed nixpkgs as its library input.
*/
{ flakePartsDir, nixpkgsDir }:
let
  inputs = {
    flakeParts = {
      outPath = flakePartsDir;
    }
    // (import (flakePartsDir + "/flake.nix")).outputs {
      self = inputs.flakeParts;
      nixpkgs-lib = inputs.nixpkgs;
    };
    nixpkgs = (import (nixpkgsDir + "/flake.nix")).outputs {
      self.outPath = nixpkgsDir;
    };
  };
in
inputs
