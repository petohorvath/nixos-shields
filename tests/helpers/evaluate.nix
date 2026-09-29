# Evaluate the exported modules without the builtin, as a consumer would.
# Each helper takes the list of modules to evaluate with.
{
  flakeParts,
  lib,
  shields,
}:
let
  # The age.shields options of a configuration built from the modules
  # alone.
  evalConfiguration = modules: (lib.evalModules { inherit modules; }).config.age.shields;
in
{
  inherit evalConfiguration;

  # As evalConfiguration, with the exported NixOS module imported too.
  evalNixosModule = modules: evalConfiguration ([ shields.nixosModules.default ] ++ modules);

  # The config of a flake that imports the exported flake-parts module
  # and the modules.
  evalFlakeModule =
    modules:
    (flakeParts.lib.evalFlakeModule { inputs.self.outPath = /nix/store/example-source; } {
      imports = [ shields.flakeModules.default ] ++ modules;
    }).config;
}
