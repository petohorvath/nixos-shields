/*
  The option tree driven through evalModules without the builtin
  present. Every case is decided before importShield reaches the
  builtin: a missing file and an empty identity list fail on their own,
  so the module's wiring of files to values is observable without a
  plugin build.
*/
{
  evalShields,
  existingShieldPath,
  ...
}:
let
  withShields = settings: evalShields [ { age.shields = settings; } ];

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
      inherit (evalShields [ ]) masterIdentities files values;
    };
    expected = {
      masterIdentities = [ ];
      files = { };
      values = { };
    };
  };

  testIdentitiesRejectRelativeStrings = {
    expr = (withShields { masterIdentities = [ "throwaway.txt" ]; }).masterIdentities;
    expectedError = {
      type = "ThrownError";
      msg = "is not of type `absolute path";
    };
  };
  testIdentitiesRejectSingleValue = {
    expr = (withShields { masterIdentities = /identity.txt; }).masterIdentities;
    expectedError = {
      type = "ThrownError";
      msg = "is not of type `list of absolute path";
    };
  };
  testFilesRejectNonPaths = {
    expr = (withShields { files.facts = 42; }).files;
    expectedError = {
      type = "ThrownError";
      msg = "is not of type `absolute path";
    };
  };

  testDirRequiredWhenReferenced = {
    expr = (evalShields [ ]).dir;
    expectedError = {
      type = "ThrownError";
      msg = "age\\.shields\\.dir' was accessed but has no value defined";
    };
  };
  testDirRejectsRelativeStrings = {
    expr = (withShields { dir = "shields"; }).dir;
    expectedError = {
      type = "ThrownError";
      msg = "is not of type `absolute path";
    };
  };
  testDirReadsBack = {
    expr = (withShields { dir = /srv/shields; }).dir;
    expected = /srv/shields;
  };
  testFilesBuiltFromDir = {
    expr = (evalShields [ wiredFromDir ]).files.facts;
    expected = /srv/shields/alpha.nix.age;
  };

  testValuesReadOnly = {
    expr = (withShields { values.facts = { }; }).values;
    expectedError = {
      type = "ThrownError";
      msg = "age\\.shields\\.values' is read-only";
    };
  };
  # Names are listable without decrypting anything.
  testValuesKeyedByFiles = {
    expr = builtins.attrNames (evalShields [ missingFile ]).values;
    expected = [ "facts" ];
  };
  testValuesFailWithoutFile = {
    expr = (evalShields [ missingFile ]).values.facts;
    expectedError = {
      type = "ThrownError";
      msg = "shield file /srv/shields/missing\\.nix\\.age does not exist";
    };
  };
  testValuesFailWithoutIdentity = {
    expr = (evalShields [ existingFile ]).values.facts;
    expectedError = {
      type = "ThrownError";
      msg = "no master identity configured";
    };
  };
}
