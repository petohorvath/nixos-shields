/*
  The public flake outputs, assembled with the supplied inputs so the
  tests exercise exactly what consumers import, and helpers that evaluate
  the exported modules without the builtin, as a consumer would. Each
  eval helper takes the list of modules to evaluate with.
*/
{ flakeParts, nixpkgs }:
let
  inherit (nixpkgs) lib;

  inputs = {
    flake-parts = flakeParts;
    inherit nixpkgs;
  };
  shields = (import ../../flake.nix).outputs (inputs // { self = shields; }) // {
    outPath = ../..;
    inherit inputs;
  };

  # A consumer's flake root. Only its path is read; it need not exist.
  flakeRoot = /example/flake;

  # The age.shields options of a configuration built from the modules
  # alone.
  evalConfiguration = modules: (lib.evalModules { inherit modules; }).config.age.shields;
in
{
  inherit evalConfiguration flakeRoot;
  shieldsLib = shields.lib;

  # The example's shield exists, so reading it gets past the file check.
  existingShieldPath = ../../examples/consumer/shields/alpha.nix.age;

  # As evalConfiguration, with the exported NixOS module imported too.
  evalNixosModule = modules: evalConfiguration ([ shields.nixosModules.default ] ++ modules);

  # The config of a flake that imports the exported flake-parts module
  # and the modules.
  evalFlakeModule =
    modules:
    (flakeParts.lib.evalFlakeModule { inputs.self.outPath = flakeRoot; } {
      imports = [ shields.flakeModules.default ] ++ modules;
    }).config;
}
