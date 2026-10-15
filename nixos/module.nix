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
        masterIdentities = [
          ./master-identities/yubikey-1.txt
          {
            identity = ./master-identities/passphrase.age;
            pubkey = "age1...";
          }
        ];
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

  # The shape of agenix-rekey's age.rekey.masterIdentities entries, so a
  # configuration can assign that option's value here.
  masterIdentityType = types.submodule {
    options = {
      identity = mkOption {
        type = types.path;
        description = "The age identity file, a path or an absolute path.";
      };
      pubkey = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          The identity's public key. When set, the command-line tool
          encrypts to it instead of presenting the identity file.
        '';
      };
    };
  };
in
{
  options.age.shields = {
    masterIdentities = mkOption {
      type = types.listOf (
        types.coercedTo types.path (identity: { inherit identity; }) masterIdentityType
      );
      default = [ ];
      description = ''
        Age identities, any one of which can decrypt every shield of
        this configuration, tried in order. An entry is an identity file
        or an attribute set with `identity` and an optional `pubkey`; a
        file alone reads back as `{ identity; pubkey = null; }`.
        Evaluating a shield with none set fails.
      '';
    };

    extraEncryptionPubkeys = mkOption {
      type = types.listOf (types.either types.path types.str);
      default = [ ];
      description = ''
        Public keys every shield is also encrypted to and that never
        decrypt, such as an offline backup key. A path or an absolute
        string names a recipients file; any other string is a public key.
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
