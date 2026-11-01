/*
  The option tree driven through evalModules without the builtin
  present. Reading a value reaches importShield, which fails for want of
  the builtin, so the module's wiring of files to values is observable
  without a plugin build. The builtin's own checks are in the
  extra-builtins suite.
*/
{ helpers, ... }:
let
  inherit (helpers) evalNixosModule;

  # The consumer's own wiring builds file locations from dir.
  wiredFromDir =
    { config, ... }:
    {
      age.shields.dir = /srv/shields;
      age.shields.files.facts = config.age.shields.dir + "/alpha.nix.age";
    };

  # agenix-rekey's age.rekey.masterIdentities declaration, copied so the
  # suite needs no agenix-rekey input.
  agenixRekeyOptions =
    { lib, ... }:
    let
      inherit (lib) mkOption types;
      identityPathType = types.coercedTo types.path toString types.str;
    in
    {
      options.age.rekey.masterIdentities = mkOption {
        type = types.listOf (
          types.coercedTo identityPathType (p: if builtins.isAttrs p then p else { identity = p; }) (
            types.submodule {
              options = {
                identity = mkOption { type = identityPathType; };
                pubkey = mkOption {
                  type = types.nullOr (
                    types.coercedTo types.path (x: if builtins.isPath x then builtins.readFile x else x) types.str
                  );
                  default = null;
                };
              };
            }
          )
        );
      };
    };

  # A master identity paired with the public key.
  pairedWith = pubkey: {
    age.shields.masterIdentities = [
      {
        identity = /srv/identities/paired.txt;
        inherit pubkey;
      }
    ];
  };

  # One public key of each kind the rule accepts.
  publicKeys = [
    "age1backup"
    "age1yubikey1backup"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI backup"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ backup"
    "age1backup\n"
  ];

  publicKeyError = option: {
    type = "ThrownError";
    msg = "age\\.shields\\.${option}.*is not a public key: it must start with age1, ssh-ed25519, or ssh-rsa";
  };

  rejectedExtraEncryptionPubkey = value: {
    expr =
      (evalNixosModule [ { age.shields.extraEncryptionPubkeys = [ value ]; } ]).extraEncryptionPubkeys;
    expectedError = publicKeyError "extraEncryptionPubkeys";
  };

  rejectedPubkey = pubkey: {
    expr = (evalNixosModule [ (pairedWith pubkey) ]).masterIdentities;
    expectedError = publicKeyError "masterIdentities.*pubkey'";
  };

  missingFile.age.shields.files.facts = /srv/shields/missing.nix.age;
in
{
  testDefaults = {
    expr = {
      inherit (evalNixosModule [ ])
        masterIdentities
        extraEncryptionPubkeys
        files
        values
        ;
    };
    expected = {
      masterIdentities = [ ];
      extraEncryptionPubkeys = [ ];
      files = { };
      values = { };
    };
  };

  # Every entry form reads back as an identity paired with its public
  # key, null when the entry declares none.
  testMasterIdentitiesCoerced = {
    expr =
      (evalNixosModule [
        {
          age.shields.masterIdentities = [
            /srv/identities/path.txt
            "/srv/identities/string.txt"
            { identity = /srv/identities/bare.txt; }
            {
              identity = /srv/identities/paired.txt;
              pubkey = "age1paired";
            }
          ];
        }
      ]).masterIdentities;
    expected = [
      {
        identity = /srv/identities/path.txt;
        pubkey = null;
      }
      {
        identity = "/srv/identities/string.txt";
        pubkey = null;
      }
      {
        identity = /srv/identities/bare.txt;
        pubkey = null;
      }
      {
        identity = /srv/identities/paired.txt;
        pubkey = "age1paired";
      }
    ];
  };

  # A configuration using agenix-rekey assigns its identities as they
  # are; agenix-rekey turns paths into absolute strings.
  testMasterIdentitiesAcceptAgenixRekeyValue = {
    expr =
      (evalNixosModule [
        agenixRekeyOptions
        (
          { config, ... }:
          {
            age.rekey.masterIdentities = [
              /srv/identities/path.txt
              {
                identity = /srv/identities/paired.txt;
                pubkey = "age1paired";
              }
            ];
            age.shields.masterIdentities = config.age.rekey.masterIdentities;
          }
        )
      ]).masterIdentities;
    expected = [
      {
        identity = "/srv/identities/path.txt";
        pubkey = null;
      }
      {
        identity = "/srv/identities/paired.txt";
        pubkey = "age1paired";
      }
    ];
  };

  # agenix-rekey reads a public key file as it is, newline included.
  testMasterIdentitiesAcceptAgenixRekeyPubkeyRead = {
    expr =
      (evalNixosModule [
        agenixRekeyOptions
        (
          { config, ... }:
          {
            age.rekey.masterIdentities = [
              {
                identity = /srv/identities/paired.txt;
                pubkey = "age1paired\n";
              }
            ];
            age.shields.masterIdentities = config.age.rekey.masterIdentities;
          }
        )
      ]).masterIdentities;
    expected = [
      {
        identity = "/srv/identities/paired.txt";
        pubkey = "age1paired\n";
      }
    ];
  };

  testMasterIdentitiesRejectRelativeString = {
    expr =
      (evalNixosModule [
        { age.shields.masterIdentities = [ "identities/relative.txt" ]; }
      ]).masterIdentities;
    expectedError = {
      type = "ThrownError";
      msg = "age\\.shields\\.masterIdentities.*is not of type";
    };
  };

  # Every kind of public key reads back as given, newline included.
  testMasterIdentitiesPubkeysReadBack = {
    expr = map (pubkey: (evalNixosModule [ (pairedWith pubkey) ]).masterIdentities) publicKeys;
    expected = map (pubkey: [
      {
        identity = /srv/identities/paired.txt;
        inherit pubkey;
      }
    ]) publicKeys;
  };
  testMasterIdentitiesRejectEmptyStringPubkey = rejectedPubkey "";
  testMasterIdentitiesRejectRelativeStringPubkey = rejectedPubkey "recipients/team.txt";
  testMasterIdentitiesRejectOtherPrefixPubkey = rejectedPubkey "ssh-dss AAAAB3NzaC1kc3MAAACBAP backup";

  # Public keys and recipients files, as paths or absolute strings, read
  # back as given.
  testExtraEncryptionPubkeysReadBack = {
    expr =
      (evalNixosModule [
        {
          age.shields.extraEncryptionPubkeys = publicKeys ++ [
            /srv/recipients/backup.txt
            "/srv/recipients/team.txt"
          ];
        }
      ]).extraEncryptionPubkeys;
    expected = publicKeys ++ [
      /srv/recipients/backup.txt
      "/srv/recipients/team.txt"
    ];
  };
  testExtraEncryptionPubkeysRejectEmptyString = rejectedExtraEncryptionPubkey "";
  # A recipients file must be a path or an absolute string.
  testExtraEncryptionPubkeysRejectRelativeString = rejectedExtraEncryptionPubkey "recipients/team.txt";
  testExtraEncryptionPubkeysRejectOtherPrefix = rejectedExtraEncryptionPubkey "ssh-dss AAAAB3NzaC1kc3MAAACBAP backup";

  testDirReadsBack = {
    expr = (evalNixosModule [ { age.shields.dir = /srv/shields; } ]).dir;
    expected = /srv/shields;
  };
  testFilesBuiltFromDir = {
    expr = (evalNixosModule [ wiredFromDir ]).files.facts;
    expected = /srv/shields/alpha.nix.age;
  };
  # The builtin takes an absolute string as it takes a path.
  testFilesAcceptAbsoluteString = {
    expr =
      (evalNixosModule [ { age.shields.files.facts = "/srv/shields/alpha.nix.age"; } ]).files.facts;
    expected = "/srv/shields/alpha.nix.age";
  };
  # The manifest reads files, so list and edit refuse the name too.
  testFilesRejectWrongSuffix = {
    expr = (evalNixosModule [ { age.shields.files.facts = /srv/shields/alpha.age; } ]).files.facts;
    expectedError = {
      type = "ThrownError";
      msg = "age\\.shields\\.files\\.facts.*is not of type.*path whose name ends in \\.nix\\.age";
    };
  };

  testValuesReadOnly = {
    expr = (evalNixosModule [ { age.shields.values.facts = { }; } ]).values;
    expectedError = {
      type = "ThrownError";
      msg = "age\\.shields\\.values' is read-only";
    };
  };
  # Names are listable without decrypting anything.
  testValuesKeyedByFiles = {
    expr = builtins.attrNames (evalNixosModule [ missingFile ]).values;
    expected = [ "facts" ];
  };
  testValuesNeedBuiltin = {
    expr = (evalNixosModule [ missingFile ]).values.facts;
    expectedError = {
      type = "ThrownError";
      msg = "importShield builtin not loaded; use the wrapped Nix from lib\\.mkNix";
    };
  };
}
