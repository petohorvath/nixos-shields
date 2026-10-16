/*
  The context every nix-unit suite receives: the kit's code imported
  from source, and helpers that evaluate its modules without the
  builtin, as a consumer would. Each eval helper takes the list of
  modules to evaluate with. flake-parts and self are null for the unit
  suites; system is accepted but unused, as no suite needs a package set.
*/
{
  flake-parts ? null,
  nixpkgs,
  self ? null,
  ...
}:
let
  inherit (nixpkgs) lib;

  fixtures = import ./fixtures;

  # The age.shields options of a configuration built from the modules
  # alone.
  evalConfiguration = modules: (lib.evalModules { inherit modules; }).config.age.shields;
in
{
  inherit fixtures lib self;
  shieldsLib = import ../lib;

  helpers = {
    inherit evalConfiguration;

    # As evalConfiguration, with the NixOS module imported too.
    evalNixosModule = modules: evalConfiguration ([ ../nixos/module.nix ] ++ modules);

    # The config of a flake that imports the flake-parts module and the
    # modules.
    evalFlakeModule =
      modules:
      (flake-parts.lib.evalFlakeModule { inputs.self.outPath = fixtures.flakeRoot; } {
        imports = [ ../flake-module.nix ] ++ modules;
      }).config;
  };
}
