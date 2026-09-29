/*
  The manifest builder and flake-parts option tree, evaluated without
  the builtin. Only public outputs are read: the manifest and options
  of configurations importing the pre-configured NixOS module.
*/
{
  evalConfigurationShields,
  evalFlake,
  evalFlakeShields,
  existingShieldPath,
  nixosModules,
  shieldsLib,
  ...
}:
let
  configured = evalFlake [
    {
      shields = {
        dir = /nix/store/example-source/shields;
        masterIdentities = [ /nix/store/example-source/master-identities/throwaway.txt ];
      };
    }
  ];

  evalConfiguration =
    modules: evalConfigurationShields ([ configured.config.shields.nixosModule ] ++ modules);

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
      inherit (evalConfiguration [ ])
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
    expr = (evalConfiguration [ nixosModules.default ]).dir;
    expected = /nix/store/example-source/shields;
  };

  testFlakePublishesManifest = {
    expr =
      (evalFlake [
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
      ]).config.flake.shields;
    expected = exampleManifest;
  };

  testValuesKeyedByFiles = {
    expr =
      builtins.attrNames
        (evalFlakeShields {
          files.shared = /nix/store/example-source/shields/shared.nix.age;
        }).values;
    expected = [ "shared" ];
  };

  testDefaults = {
    expr = {
      inherit (evalFlakeShields { })
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
    expr = (evalFlakeShields { }).dir;
    expectedError = {
      type = "ThrownError";
      msg = "shields\\.dir' was accessed but has no value defined";
    };
  };
  testDirRejectsRelativeStrings = {
    expr = (evalFlakeShields { dir = "shields"; }).dir;
    expectedError = {
      type = "ThrownError";
      msg = "is not of type `absolute path";
    };
  };
  testIdentitiesRejectNonPaths = {
    expr = (evalFlakeShields { masterIdentities = [ 42 ]; }).masterIdentities;
    expectedError = {
      type = "ThrownError";
      msg = "is not of type `absolute path";
    };
  };
  testFilesRejectNonPaths = {
    expr = (evalFlakeShields { files.shared = 42; }).files;
    expectedError = {
      type = "ThrownError";
      msg = "is not of type `absolute path";
    };
  };
  testValuesReadOnly = {
    expr = (evalFlakeShields { values.shared = { }; }).values;
    expectedError = {
      type = "ThrownError";
      msg = "shields\\.values' is read-only";
    };
  };
  testNixosModuleReadOnly = {
    expr = (evalFlakeShields { nixosModule = { }; }).nixosModule;
    expectedError = {
      type = "ThrownError";
      msg = "shields\\.nixosModule' is read-only";
    };
  };

  testValuesFailWithoutFile = {
    expr =
      (evalFlakeShields {
        files.shared = /nix/store/example-source/shields/missing.nix.age;
      }).values.shared;
    expectedError = {
      type = "ThrownError";
      msg = "shields/missing\\.nix\\.age does not exist";
    };
  };
  testValuesFailWithoutIdentity = {
    expr = (evalFlakeShields { files.shared = existingShieldPath; }).values.shared;
    expectedError = {
      type = "ThrownError";
      msg = "no master identity configured";
    };
  };

  testNixosModuleDefaultsOverridden = {
    expr = {
      inherit
        (evalConfiguration [
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
    expr = (evalConfiguration [ { age.shields.masterIdentities = [ ]; } ]).masterIdentities;
    expected = [ ];
  };

  testNixosModuleWiresFilesFromDir = {
    expr =
      (evalConfiguration [
        ({ config, ... }: { age.shields.files.facts = config.age.shields.dir + "/alpha.nix.age"; })
      ]).files.facts;
    expected = /nix/store/example-source/shields/alpha.nix.age;
  };

  testConfigurationsCanUseAnotherOutput = {
    expr =
      (evalFlake [
        {
          flake.nixosConfigurations.unused = throw "the default configurations must not be evaluated";
          shields.configurations.beta.config.age.shields.files.facts =
            /nix/store/example-source/shields/beta.nix.age;
        }
      ]).config.flake.shields.configurations;
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
