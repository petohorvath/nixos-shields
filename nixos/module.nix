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
  inherit (lib)
    hasSuffix
    mapAttrs
    mkOption
    mkOptionType
    showOption
    types
    ;
  inherit (lib.options) mergeEqualOption showDefs;

  importShield = import ../lib/import-shield.nix (builtins.extraBuiltins or null);
  inherit (import ../lib/public-key.nix) isPublicKey notPublicKeyMessage;

  cfg = config.age.shields;

  # The builtin's file rule, checked here too so the manifest, and with
  # it list and edit, refuse a name the builtin would.
  shieldFileType = types.addCheck types.path (file: hasSuffix ".nix.age" (baseNameOf file)) // {
    description = "path whose name ends in .nix.age";
  };

  /*
    A string satisfying the public-key rule. Any string passes the type
    check and a bad one fails on merge instead, so the failure states
    the rule and `types.either types.path` still takes an absolute
    string as a path.
  */
  publicKeyType = mkOptionType {
    name = "publicKey";
    description = "public key";
    descriptionClass = "noun";
    check = builtins.isString;
    merge =
      loc: defs:
      let
        key = mergeEqualOption loc defs;
      in
      if isPublicKey key then
        key
      else
        throw "A definition for option `${showOption loc}' ${notPublicKeyMessage}. Definition values:${showDefs defs}";
  };

  # The shape of agenix-rekey's age.rekey.masterIdentities entries, so a
  # configuration can assign that option's value here.
  masterIdentityType = types.submodule {
    options = {
      identity = mkOption {
        type = types.path;
        description = "The age identity file, a path or an absolute path.";
      };
      pubkey = mkOption {
        type = types.nullOr publicKeyType;
        default = null;
        description = ''
          The identity's public key, starting with `age1`,
          `ssh-ed25519 `, or `ssh-rsa `. When set, the command-line tool
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
      type = types.listOf (types.either types.path publicKeyType);
      default = [ ];
      description = ''
        Public keys every shield is also encrypted to and that never
        decrypt, such as an offline backup key. A path or an absolute
        string names a recipients file; any other string must be a public
        key, starting with `age1`, `ssh-ed25519 `, or `ssh-rsa `.
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
      type = types.attrsOf shieldFileType;
      default = { };
      description = ''
        Shield files by name, each a path or an absolute path string
        whose name ends in `.nix.age`. Each is decrypted into
        `values.<name>`; a file that does not exist fails evaluation
        with its location.
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
