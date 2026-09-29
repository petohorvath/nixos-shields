/*
  age.shields — exposes a configuration's shields as options. Every
  file under `files` is decrypted with `masterIdentities` and its value
  published under `values.<name>`, readable by any module of the
  configuration. Reading a value needs the wrapped Nix (lib.mkNix).

  The module knows nothing about how a consumer lays out its shield
  files: `dir` is never read by the kit and exists so the consumer's
  own wiring can build file locations from it.

  Example:
    { config, ... }:
    {
      imports = [ nixos-shields.nixosModules.default ];
      age.shields = {
        masterIdentities = [ ./master-identities/yubikey-1.txt ];
        dir = ./shields;
        files.facts = config.age.shields.dir + "/alpha.nix.age";
      };
      networking.domain = config.age.shields.values.facts.domain;
    }
*/
{ config, lib, ... }:
let
  inherit (lib) mapAttrs mkOption types;

  importShield = import ../lib/import-shield.nix;

  cfg = config.age.shields;
in
{
  options.age.shields = {
    masterIdentities = mkOption {
      type = types.listOf types.path;
      default = [ ];
      description = ''
        Age identity files, any one of which can decrypt every shield of
        this configuration. Evaluating a shield with none set fails.
      '';
    };

    dir = mkOption {
      type = types.path;
      description = ''
        The directory holding this configuration's shield files. Not
        read by the kit; consumers build `files` locations from it.
      '';
    };

    files = mkOption {
      type = types.attrsOf types.path;
      default = { };
      description = ''
        Shield files by name. Each is decrypted into `values.<name>`;
        a file that does not exist fails evaluation with its location.
      '';
    };

    values = mkOption {
      type = types.lazyAttrsOf types.raw;
      readOnly = true;
      description = ''
        The decrypted value of each shield in `files`, by name. Derived
        by the module; each value is read only when something uses it.
      '';
    };
  };

  config.age.shields.values = mapAttrs (_: importShield cfg.masterIdentities) cfg.files;
}
