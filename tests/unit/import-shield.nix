# lib.importShield applied to a fake builtin: which identity of each
# entry form reaches the builtin, the entry-form checks, and the failure
# when the running Nix lacks the builtin.
{
  fixtures,
  helpers,
  internal,
  lib,
  ...
}:
let
  inherit (fixtures) existingShieldPath;

  importShieldWith = internal.importShield;
  importShield = importShieldWith helpers.fakeExtraBuiltins;
  noBuiltin = "nixos-shields: importShield builtin not loaded; use the wrapped Nix from lib\\.mkNix";

  # Master identities that break an entry-form check, keyed by the name
  # their tests carry, with the message that names the check. Each fails
  # at its last entry, so the message shows the position.
  badIdentities = {
    NonList = {
      identities = /srv/identities/path.txt;
      msg = "nixos-shields: the master identities must be a list of paths, absolute path strings, or \\{ identity; pubkey; }";
    };
    EntryOfAnotherType = {
      identities = [
        /srv/identities/path.txt
        42
      ];
      msg = "nixos-shields: master identity entry 2 must be a path, an absolute path string, or \\{ identity; pubkey; }";
    };
    EntryWithoutIdentity = {
      identities = [
        /srv/identities/path.txt
        { pubkey = "age1paired"; }
      ];
      msg = "nixos-shields: master identity entry 2 has no identity";
    };
    # A typo such as pubKey is not silently ignored.
    EntryWithUnknownAttribute = {
      identities = [
        {
          identity = /srv/identities/paired.txt;
          pubKey = "age1paired";
        }
      ];
      msg = "nixos-shields: master identity entry 1 has the unknown attribute pubKey; it takes only identity and pubkey";
    };
    # A paired public key follows the rule the NixOS module enforces.
    EntryWithInvalidPubkey = {
      identities = [
        /srv/identities/path.txt
        "/srv/identities/string.txt"
        {
          identity = /srv/identities/paired.txt;
          pubkey = "recipients/team.txt";
        }
      ];
      msg = "nixos-shields: the pubkey of master identity entry 3 is not a public key: it must start with age1, ssh-ed25519, or ssh-rsa";
    };
  };

  # Each bad argument fails its check with the builtin loaded.
  badIdentitiesRejected = lib.mapAttrs' (
    name: bad:
    lib.nameValuePair "testRejects${name}" {
      expr = importShield bad.identities existingShieldPath;
      expectedError = {
        type = "ThrownError";
        inherit (bad) msg;
      };
    }
  ) badIdentities;

  # The missing builtin takes priority over every entry-form check.
  badIdentitiesWithoutBuiltin = lib.mapAttrs' (
    name: bad:
    lib.nameValuePair "test${name}FailsWithoutBuiltin" {
      expr = importShieldWith null bad.identities existingShieldPath;
      expectedError = {
        type = "ThrownError";
        msg = noBuiltin;
      };
    }
  ) badIdentities;
in
badIdentitiesRejected
// badIdentitiesWithoutBuiltin
// {
  # A public key cannot decrypt, so only the identity of a paired entry
  # reaches the builtin.
  testPassesIdentitiesOfEveryEntryForm = {
    expr = importShield [
      /srv/identities/path.txt
      "/srv/identities/string.txt"
      { identity = /srv/identities/bare.txt; }
      {
        identity = /srv/identities/unpaired.txt;
        pubkey = null;
      }
      {
        identity = "/srv/identities/paired.txt";
        pubkey = "age1paired";
      }
    ] existingShieldPath;
    expected = [
      "@decrypt@"
      existingShieldPath
      /srv/identities/path.txt
      "/srv/identities/string.txt"
      /srv/identities/bare.txt
      /srv/identities/unpaired.txt
      "/srv/identities/paired.txt"
    ];
  };

  # A Nix without nix-plugins has no extraBuiltins.
  testFailsWithoutExtraBuiltins = {
    expr = importShieldWith null [ /srv/identities/path.txt ] existingShieldPath;
    expectedError = {
      type = "ThrownError";
      msg = noBuiltin;
    };
  };
  # A Nix with nix-plugins can load an extra-builtins file other than the
  # kit's.
  testFailsWithoutImportShield = {
    expr = importShieldWith { consumerAnswer = 42; } [ /srv/identities/path.txt ] existingShieldPath;
    expectedError = {
      type = "ThrownError";
      msg = noBuiltin;
    };
  };
  # The builtin owns the file check, so a missing file without the
  # builtin names lib.mkNix too.
  testMissingFileFailsWithoutBuiltin = {
    expr = importShieldWith null [ /srv/identities/path.txt ] /srv/shields/missing.nix.age;
    expectedError = {
      type = "ThrownError";
      msg = noBuiltin;
    };
  };
}
