/*
  The option tree driven through evalModules without the builtin
  present. Every case is decided before importShield reaches the
  builtin: a missing file and an empty identity list fail on their own,
  so the module's wiring of files to values is observable without a
  plugin build.
*/
{
  evalNixosModule,
  existingShieldPath,
  ...
}:
let
  # The consumer's own wiring builds file locations from dir.
  wiredFromDir =
    { config, ... }:
    {
      age.shields.dir = /srv/shields;
      age.shields.files.facts = config.age.shields.dir + "/alpha.nix.age";
    };

  missingFile.age.shields.files.facts = /srv/shields/missing.nix.age;
  existingFile.age.shields.files.facts = existingShieldPath;
in
{
  testDefaults = {
    expr = {
      inherit (evalNixosModule [ ]) masterIdentities files values;
    };
    expected = {
      masterIdentities = [ ];
      files = { };
      values = { };
    };
  };

  testIdentitiesRejectRelativeStrings = {
    expr =
      (evalNixosModule [ { age.shields.masterIdentities = [ "throwaway.txt" ]; } ]).masterIdentities;
    expectedError = {
      type = "ThrownError";
      msg = "is not of type `absolute path";
    };
  };
  testIdentitiesRejectSingleValue = {
    expr = (evalNixosModule [ { age.shields.masterIdentities = /identity.txt; } ]).masterIdentities;
    expectedError = {
      type = "ThrownError";
      msg = "is not of type `list of absolute path";
    };
  };
  testFilesRejectNonPaths = {
    expr = (evalNixosModule [ { age.shields.files.facts = 42; } ]).files;
    expectedError = {
      type = "ThrownError";
      msg = "is not of type `absolute path";
    };
  };

  testDirRequiredWhenReferenced = {
    expr = (evalNixosModule [ ]).dir;
    expectedError = {
      type = "ThrownError";
      msg = "age\\.shields\\.dir' was accessed but has no value defined";
    };
  };
  testDirRejectsRelativeStrings = {
    expr = (evalNixosModule [ { age.shields.dir = "shields"; } ]).dir;
    expectedError = {
      type = "ThrownError";
      msg = "is not of type `absolute path";
    };
  };
  testDirReadsBack = {
    expr = (evalNixosModule [ { age.shields.dir = /srv/shields; } ]).dir;
    expected = /srv/shields;
  };
  testFilesBuiltFromDir = {
    expr = (evalNixosModule [ wiredFromDir ]).files.facts;
    expected = /srv/shields/alpha.nix.age;
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
  testValuesFailWithoutFile = {
    expr = (evalNixosModule [ missingFile ]).values.facts;
    expectedError = {
      type = "ThrownError";
      msg = "shield file /srv/shields/missing\\.nix\\.age does not exist";
    };
  };
  testValuesFailWithoutIdentity = {
    expr = (evalNixosModule [ existingFile ]).values.facts;
    expectedError = {
      type = "ThrownError";
      msg = "no master identity configured";
    };
  };
}
