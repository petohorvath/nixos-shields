/*
  Load the unit test suites for nix-unit; nix-unit checks their
  expectations. Direct runs use the root flake's locked inputs; the
  flake check supplies both arguments.

  Example: nix-unit tests/entrypoint.nix --attr nixosModule
*/
let
  rootInputs = (builtins.getFlake (toString ../.)).inputs;

  # Use the selected nixpkgs for flake-parts too, including overrides.
  flakePartsFor =
    nixpkgs:
    (import ./helpers/evaluation-inputs.nix {
      flakePartsDir = rootInputs.flake-parts.outPath;
      nixpkgsDir = nixpkgs.outPath;
    }).flakeParts;
in
{
  nixpkgs ? rootInputs.nixpkgs,
  flakeParts ? flakePartsFor nixpkgs,
}:
import ./suites {
  testContext = import ./helpers/test-context.nix { inherit flakeParts nixpkgs; };
}
