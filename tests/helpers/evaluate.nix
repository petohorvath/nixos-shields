# Evaluate the exported modules without the builtin, as a consumer would.
{
  flakeParts,
  lib,
  shields,
}:
let
  # The age.shields options of a configuration built from the modules.
  evalConfigurationShields = modules: (lib.evalModules { inherit modules; }).config.age.shields;

  evalFlake =
    modules:
    flakeParts.lib.evalFlakeModule { inputs.self.outPath = /nix/store/example-source; } {
      imports = [ shields.flakeModules.default ] ++ modules;
    };
in
{
  inherit evalConfigurationShields evalFlake;

  # As evalConfigurationShields, with the exported NixOS module imported.
  evalShields = modules: evalConfigurationShields ([ shields.nixosModules.default ] ++ modules);

  # The flake module's shields options with the given settings.
  evalFlakeShields = settings: (evalFlake [ { shields = settings; } ]).config.shields;
}
