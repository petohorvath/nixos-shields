/*
  Flake-scoped shields and a pre-configured NixOS module. The consumer
  supplies the module libraries; this module imports no flake inputs.
*/
{
  config,
  lib,
  self,
  ...
}:
let
  inherit (lib)
    literalExpression
    mapAttrs
    mkDefault
    mkOption
    types
    ;

  importShield = import ./lib/import-shield.nix;
  mkManifest = import ./lib/mk-manifest.nix;

  cfg = config.shields;
in
{
  _class = "flake";

  options.shields = {
    dir = mkOption {
      type = types.path;
      description = ''
        The shield directory, passed to configurations as a default.
        Consumers decide how to build file locations from it.
      '';
    };

    masterIdentities = mkOption {
      type = types.listOf types.path;
      default = [ ];
      description = ''
        Age identity files shared by flake-scoped shields and, by
        default, every configuration. Reading a shield with none fails.
      '';
    };

    files = mkOption {
      type = types.attrsOf types.path;
      default = { };
      description = ''
        Flake-scoped shield files by name. Each is decrypted into
        `values.<name>` when that value is read.
      '';
    };

    values = mkOption {
      type = types.lazyAttrsOf types.raw;
      readOnly = true;
      description = ''
        Decrypted flake-scoped values, by shield name. Each is read only
        when used and is available before any configuration evaluates.
        Reading a value needs the wrapped Nix from lib.mkNix.
      '';
    };

    configurations = mkOption {
      type = types.lazyAttrsOf types.raw;
      default = config.flake.nixosConfigurations;
      defaultText = literalExpression "config.flake.nixosConfigurations";
      description = ''
        Evaluated configurations whose shield files enter the manifest.
        Set this when configurations live in a different flake output.
        Configurations without the shields module have no shield files.
      '';
    };

    nixosModule = mkOption {
      type = types.deferredModule;
      readOnly = true;
      description = ''
        The kit's NixOS module with the flake's directory and master
        identities as low-priority defaults. Import it in a configuration
        and declare that configuration's shield files there.
      '';
    };
  };

  config = {
    shields.values = mapAttrs (_: importShield cfg.masterIdentities) cfg.files;

    shields.nixosModule = {
      imports = [ ./nixos/module.nix ];
      age.shields = {
        dir = mkDefault cfg.dir;
        masterIdentities = mkDefault cfg.masterIdentities;
      };
    };

    flake.shields = mkManifest {
      inherit self;
      inherit (cfg) masterIdentities files configurations;
    };
  };
}
