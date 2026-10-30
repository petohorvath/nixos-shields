# The importShield builtin, imported from source with a fake exec that
# returns its argv: the checks it makes before decrypting, and the
# command it hands to exec.
{ fakeExtraBuiltins, fixtures, ... }:
let
  inherit (fakeExtraBuiltins) importShield;
  inherit (fixtures) existingShieldPath;

  existingShieldString = toString existingShieldPath;
in
{
  # Paths and absolute strings reach exec as given, after the program.
  testPassesPathsToExec = {
    expr = importShield [ /srv/identities/path.txt ] existingShieldPath;
    expected = [
      "@decrypt@"
      existingShieldPath
      /srv/identities/path.txt
    ];
  };
  testPassesAbsoluteStringsToExec = {
    expr = importShield [
      "/srv/identities/string.txt"
      /srv/identities/path.txt
    ] existingShieldString;
    expected = [
      "@decrypt@"
      existingShieldString
      "/srv/identities/string.txt"
      /srv/identities/path.txt
    ];
  };

  testRejectsEmptyIdentityList = {
    expr = importShield [ ] existingShieldPath;
    expectedError = {
      type = "ThrownError";
      msg = "nixos-shields: no master identity configured; cannot decrypt .*alpha\\.nix\\.age";
    };
  };
  testRejectsRelativeIdentityString = {
    expr = importShield [ "identities/relative.txt" ] existingShieldPath;
    expectedError = {
      type = "ThrownError";
      msg = "nixos-shields: the master identities must be a list of paths or absolute path strings";
    };
  };
  testRejectsIdentityNotInList = {
    expr = importShield /srv/identities/path.txt existingShieldPath;
    expectedError = {
      type = "ThrownError";
      msg = "nixos-shields: the master identities must be a list";
    };
  };

  testRejectsRelativeFileString = {
    expr = importShield [ /srv/identities/path.txt ] "shields/alpha.nix.age";
    expectedError = {
      type = "ThrownError";
      msg = "nixos-shields: shield file shields/alpha\\.nix\\.age must be a path or an absolute path string";
    };
  };
  testRejectsWrongSuffix = {
    expr = importShield [ /srv/identities/path.txt ] /srv/shields/alpha.age;
    expectedError = {
      type = "ThrownError";
      msg = "nixos-shields: shield file name must end in \\.nix\\.age: /srv/shields/alpha\\.age";
    };
  };
  testRejectsMissingPath = {
    expr = importShield [ /srv/identities/path.txt ] /srv/shields/missing.nix.age;
    expectedError = {
      type = "ThrownError";
      msg = "nixos-shields: shield file /srv/shields/missing\\.nix\\.age does not exist";
    };
  };
  testRejectsMissingString = {
    expr = importShield [ /srv/identities/path.txt ] "/srv/shields/missing.nix.age";
    expectedError = {
      type = "ThrownError";
      msg = "nixos-shields: shield file /srv/shields/missing\\.nix\\.age does not exist";
    };
  };
}
