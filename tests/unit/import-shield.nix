# lib.importShield applied to a fake builtin: which identity of each
# entry form reaches the builtin, and the failure when the running Nix
# lacks the builtin.
{
  fakeExtraBuiltins,
  fixtures,
  importShieldWith,
  ...
}:
let
  inherit (fixtures) existingShieldPath;

  importShield = importShieldWith fakeExtraBuiltins;
  noBuiltin = "nixos-shields: importShield builtin not loaded; use the wrapped Nix from lib\\.mkNix";
in
{
  # A public key cannot decrypt, so only the identity of a paired entry
  # reaches the builtin.
  testPassesIdentitiesOfEveryEntryForm = {
    expr = importShield [
      /srv/identities/path.txt
      "/srv/identities/string.txt"
      { identity = /srv/identities/bare.txt; }
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
  # Another extra-builtins file can be loaded instead of the kit's.
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
