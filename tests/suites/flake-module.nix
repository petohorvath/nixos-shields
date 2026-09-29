/*
  The manifest builder and flake-parts option tree, evaluated without
  the builtin. Only public outputs are read: the manifest and options
  of configurations importing the pre-configured NixOS module.
*/
{
  evalConfiguration,
  evalFlakeModule,
  evalNixosModule,
  existingShieldPath,
  shieldsLib,
  ...
}:
let
  # The pre-configured NixOS module of a flake with a directory and a
  # master identity.
  preconfiguredModule =
    (evalFlakeModule [
      {
        shields = {
          dir = /nix/store/example-source/shields;
          masterIdentities = [ /nix/store/example-source/master-identities/throwaway.txt ];
        };
      }
    ]).shields.nixosModule;

  exampleManifest = {
    masterIdentities = [ "master-identities/throwaway.txt" ];
    files.shared = "shields/shared.nix.age";
    configurations.alpha.files.facts = "shields/alpha.nix.age";
  };
in
{
  testManifestRelativeLocations = {
    expr = shieldsLib.mkManifest {
      self.outPath = /nix/store/example-source;
      masterIdentities = [ /nix/store/example-source/master-identities/throwaway.txt ];
      files.shared = /nix/store/example-source/shields/shared.nix.age;
      configurations.alpha.config.age.shields.files.facts =
        /nix/store/example-source/shields/alpha.nix.age;
    };
    expected = exampleManifest;
  };

  testNixosModuleInheritsDefaults = {
    expr = {
      inherit (evalConfiguration [ preconfiguredModule ])
        dir
        files
        masterIdentities
        values
        ;
    };
    expected = {
      dir = /nix/store/example-source/shields;
      files = { };
      masterIdentities = [ /nix/store/example-source/master-identities/throwaway.txt ];
      values = { };
    };
  };

  # Both modules declare age.shields; importing both must not declare it
  # twice.
  testNixosModuleImportsWithDefaultModule = {
    expr = (evalNixosModule [ preconfiguredModule ]).dir;
    expected = /nix/store/example-source/shields;
  };

  testFlakePublishesManifest = {
    expr =
      (evalFlakeModule [
        {
          shields = {
            masterIdentities = [ /nix/store/example-source/master-identities/throwaway.txt ];
            files.shared = /nix/store/example-source/shields/shared.nix.age;
          };
          flake.nixosConfigurations.alpha = {
            config.age.shields = {
              files.facts = /nix/store/example-source/shields/alpha.nix.age;
              values = throw "the manifest must not decrypt shields";
            };
          };
        }
      ]).flake.shields;
    expected = exampleManifest;
  };

  testValuesKeyedByFiles = {
    expr =
      builtins.attrNames
        (evalFlakeModule [
          { shields.files.shared = /nix/store/example-source/shields/shared.nix.age; }
        ]).shields.values;
    expected = [ "shared" ];
  };

  testDefaults = {
    expr = {
      inherit ((evalFlakeModule [ ]).shields)
        configurations
        files
        masterIdentities
        values
        ;
    };
    expected = {
      configurations = { };
      files = { };
      masterIdentities = [ ];
      values = { };
    };
  };

  testDirRequiredWhenReferenced = {
    expr = (evalFlakeModule [ ]).shields.dir;
    expectedError = {
      type = "ThrownError";
      msg = "shields\\.dir' was accessed but has no value defined";
    };
  };
  testDirRejectsRelativeStrings = {
    expr = (evalFlakeModule [ { shields.dir = "shields"; } ]).shields.dir;
    expectedError = {
      type = "ThrownError";
      msg = "is not of type `absolute path";
    };
  };
  testIdentitiesRejectNonPaths = {
    expr = (evalFlakeModule [ { shields.masterIdentities = [ 42 ]; } ]).shields.masterIdentities;
    expectedError = {
      type = "ThrownError";
      msg = "is not of type `absolute path";
    };
  };
  testFilesRejectNonPaths = {
    expr = (evalFlakeModule [ { shields.files.shared = 42; } ]).shields.files;
    expectedError = {
      type = "ThrownError";
      msg = "is not of type `absolute path";
    };
  };
  testValuesReadOnly = {
    expr = (evalFlakeModule [ { shields.values.shared = { }; } ]).shields.values;
    expectedError = {
      type = "ThrownError";
      msg = "shields\\.values' is read-only";
    };
  };
  testNixosModuleReadOnly = {
    expr = (evalFlakeModule [ { shields.nixosModule = { }; } ]).shields.nixosModule;
    expectedError = {
      type = "ThrownError";
      msg = "shields\\.nixosModule' is read-only";
    };
  };

  testValuesFailWithoutFile = {
    expr =
      (evalFlakeModule [
        { shields.files.shared = /nix/store/example-source/shields/missing.nix.age; }
      ]).shields.values.shared;
    expectedError = {
      type = "ThrownError";
      msg = "shields/missing\\.nix\\.age does not exist";
    };
  };
  testValuesFailWithoutIdentity = {
    expr = (evalFlakeModule [ { shields.files.shared = existingShieldPath; } ]).shields.values.shared;
    expectedError = {
      type = "ThrownError";
      msg = "no master identity configured";
    };
  };

  testNixosModuleDefaultsOverridden = {
    expr = {
      inherit
        (evalConfiguration [
          preconfiguredModule
          {
            age.shields = {
              dir = /srv/another-directory;
              masterIdentities = [ /srv/another-identity.txt ];
            };
          }
        ])
        dir
        masterIdentities
        ;
    };
    expected = {
      dir = /srv/another-directory;
      masterIdentities = [ /srv/another-identity.txt ];
    };
  };

  testNixosModuleIdentitiesCanBeCleared = {
    expr =
      (evalConfiguration [
        preconfiguredModule
        { age.shields.masterIdentities = [ ]; }
      ]).masterIdentities;
    expected = [ ];
  };

  testNixosModuleWiresFilesFromDir = {
    expr =
      (evalConfiguration [
        preconfiguredModule
        ({ config, ... }: { age.shields.files.facts = config.age.shields.dir + "/alpha.nix.age"; })
      ]).files.facts;
    expected = /nix/store/example-source/shields/alpha.nix.age;
  };

  testConfigurationsCanUseAnotherOutput = {
    expr =
      (evalFlakeModule [
        {
          flake.nixosConfigurations.unused = throw "the default configurations must not be evaluated";
          shields.configurations.beta.config.age.shields.files.facts =
            /nix/store/example-source/shields/beta.nix.age;
        }
      ]).flake.shields.configurations;
    expected = {
      beta.files.facts = "shields/beta.nix.age";
    };
  };

  testManifestDefaults = {
    expr = shieldsLib.mkManifest { self.outPath = /nix/store/example-source; };
    expected = {
      masterIdentities = [ ];
      files = { };
      configurations = { };
    };
  };

  testManifestIncludesUnshieldedConfigurations = {
    expr =
      (shieldsLib.mkManifest {
        self.outPath = /nix/store/example-source;
        configurations.unshielded.config.networking.hostName = "unshielded";
      }).configurations;
    expected = {
      unshielded.files = { };
    };
  };

  testManifestAcceptsAbsoluteStrings = {
    expr = shieldsLib.mkManifest {
      self.outPath = "/nix/store/example-source";
      masterIdentities = [ "/nix/store/example-source/master-identities/throwaway.txt" ];
      files.shared = "/nix/store/example-source/shields/shared.nix.age";
    };
    expected = {
      masterIdentities = [ "master-identities/throwaway.txt" ];
      files.shared = "shields/shared.nix.age";
      configurations = { };
    };
  };

  testManifestRejectsOtherRoots = {
    expr = shieldsLib.mkManifest {
      self.outPath = /nix/store/example-source;
      files.shared = /nix/store/example-source-other/shields/shared.nix.age;
    };
    expectedError = {
      type = "ThrownError";
      msg = "is outside flake root /nix/store/example-source$";
    };
  };

  testManifestRejectsIdentityOutsideRoot = {
    expr = shieldsLib.mkManifest {
      self.outPath = /nix/store/example-source;
      masterIdentities = [ /srv/identity.txt ];
    };
    expectedError = {
      type = "ThrownError";
      msg = "manifest path /srv/identity\\.txt is outside flake root";
    };
  };

  testManifestRejectsEscapingString = {
    expr = shieldsLib.mkManifest {
      self.outPath = "/nix/store/example-source";
      files.shared = "/nix/store/example-source/../outside.nix.age";
    };
    expectedError = {
      type = "ThrownError";
      msg = "manifest path /nix/store/outside\\.nix\\.age is outside flake root";
    };
  };

  testManifestNormalizesStringLocations = {
    expr =
      (shieldsLib.mkManifest {
        self.outPath = "/nix/store/example-source/.";
        files.shared = "/nix/store/example-source/shields/nested/../shared.nix.age";
      }).files.shared;
    expected = "shields/shared.nix.age";
  };
}
