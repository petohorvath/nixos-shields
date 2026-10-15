# Publishes the manifest of a flake-parts flake. Configurations import
# nixosModules.default themselves; this module imports no flake inputs.
{
  config,
  lib,
  self,
  ...
}:
let
  inherit (lib) literalExpression mkOption types;

  mkManifest = import ./lib/mk-manifest.nix;

  cfg = config.shields;
in
{
  _class = "flake";

  options.shields.configurations = mkOption {
    type = types.lazyAttrsOf types.raw;
    default = config.flake.nixosConfigurations;
    defaultText = literalExpression "config.flake.nixosConfigurations";
    description = ''
      Evaluated configurations whose shield files and master identities
      enter the manifest. Set this when configurations live in a
      different flake output. Configurations without the shields module
      have no shield files.
    '';
  };

  config.flake.shields = mkManifest {
    inherit self;
    inherit (cfg) configurations;
  };
}
