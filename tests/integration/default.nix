# The integration suites for nix-unit. Local runs default to the root
# flake's locked inputs; the integration check passes every argument.
#
# Example: nix-unit tests/integration --attr flake-module
let
  rootInputs = (builtins.getFlake (toString ../..)).inputs;
  rebuild = import ../helpers/evaluation-inputs.nix;
in
{
  nixpkgs ? rootInputs.nixpkgs,
  # flake-parts follows nixpkgs, so rebuild it against the selected one.
  flake-parts ? rebuild {
    path = rootInputs.flake-parts.outPath;
    inputs.nixpkgs-lib = nixpkgs;
  },
  system ? builtins.currentSystem,
}:
let
  testContext = import ../test-context.nix { inherit flake-parts nixpkgs system; };
in
{
  flake-module = import ./flake-module.nix testContext;
  flake-outputs = import ./flake-outputs.nix testContext;
}
