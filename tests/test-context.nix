/*
  The context every nix-unit suite receives: the kit's code imported
  from source, and helpers that evaluate its modules without the
  builtin, as a consumer would. Each eval helper takes the list of
  modules to evaluate with. flake-parts is null for the unit suites.
*/
{
  flake-parts ? null,
  nixpkgs,
  system,
}:
let
  inherit (nixpkgs) lib;

  fixtures = import ./fixtures;

  # The age.shields options of a configuration built from the modules
  # alone.
  evalConfiguration = modules: (lib.evalModules { inherit modules; }).config.age.shields;
in
{
  inherit fixtures lib;
  pkgs = nixpkgs.legacyPackages.${system};
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

    # The public flake outputs, assembled with the given inputs, as
    # consumers see them.
    flakeOutputs =
      let
        inputs = {
          inherit flake-parts;
          # flake-parts' inputs' accepts only flakes, and
          # helpers/evaluation-inputs.nix does not mark its rebuilt
          # flakes as such.
          nixpkgs = nixpkgs // {
            _type = "flake";
          };
        };
        self = (import ../flake.nix).outputs (inputs // { inherit self; }) // {
          outPath = ../.;
          inherit inputs;
        };
      in
      self;
  };
}
