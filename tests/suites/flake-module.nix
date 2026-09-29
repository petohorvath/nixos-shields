/*
  The manifest builder and flake-parts option tree, evaluated without
  the builtin. Only public outputs are read: the manifest and options
  of configurations importing the pre-configured NixOS module.
*/
{
  evalConfiguration,
  evalFlakeModule,
  evalNixosModule,
  flakeRoot,
  shieldsLib,
  ...
}:
let
  root = toString flakeRoot;
  shieldsDir = flakeRoot + "/shields";
  identityPath = flakeRoot + "/master-identities/throwaway.txt";
  sharedShieldPath = shieldsDir + "/shared.nix.age";
  alphaShieldPath = shieldsDir + "/alpha.nix.age";

  # The pre-configured NixOS module of a flake with a directory and a
  # master identity.
  preconfiguredModule =
    (evalFlakeModule [
      {
        shields = {
          dir = shieldsDir;
          masterIdentities = [ identityPath ];
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
      self.outPath = flakeRoot;
      masterIdentities = [ identityPath ];
      files.shared = sharedShieldPath;
      configurations.alpha.config.age.shields.files.facts = alphaShieldPath;
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
      dir = shieldsDir;
      files = { };
      masterIdentities = [ identityPath ];
      values = { };
    };
  };

  # Both modules declare age.shields; importing both must not declare it
  # twice.
  testNixosModuleImportsWithDefaultModule = {
    expr = (evalNixosModule [ preconfiguredModule ]).dir;
    expected = shieldsDir;
  };

  testFlakePublishesManifest = {
    expr =
      (evalFlakeModule [
        {
          shields = {
            masterIdentities = [ identityPath ];
            files.shared = sharedShieldPath;
          };
          flake.nixosConfigurations.alpha = {
            config.age.shields = {
              files.facts = alphaShieldPath;
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
          { shields.files.shared = sharedShieldPath; }
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

  testValuesReadOnly = {
    expr = (evalFlakeModule [ { shields.values.shared = { }; } ]).shields.values;
    expectedError = {
      type = "ThrownError";
      msg = "shields\\.values' is read-only";
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
    expected = alphaShieldPath;
  };

  testConfigurationsCanUseAnotherOutput = {
    expr =
      (evalFlakeModule [
        {
          flake.nixosConfigurations.unused = throw "the default configurations must not be evaluated";
          shields.configurations.beta.config.age.shields.files.facts = shieldsDir + "/beta.nix.age";
        }
      ]).flake.shields.configurations;
    expected = {
      beta.files.facts = "shields/beta.nix.age";
    };
  };

  # Also covers the defaults of the omitted arguments.
  testManifestIncludesUnshieldedConfigurations = {
    expr = shieldsLib.mkManifest {
      self.outPath = flakeRoot;
      configurations.unshielded.config.networking.hostName = "unshielded";
    };
    expected = {
      masterIdentities = [ ];
      files = { };
      configurations.unshielded.files = { };
    };
  };

  testManifestAcceptsAbsoluteStrings = {
    expr = shieldsLib.mkManifest {
      self.outPath = root;
      masterIdentities = [ (toString identityPath) ];
      files.shared = toString sharedShieldPath;
    };
    expected = {
      masterIdentities = [ "master-identities/throwaway.txt" ];
      files.shared = "shields/shared.nix.age";
      configurations = { };
    };
  };

  testManifestRejectsEscapingString = {
    expr = shieldsLib.mkManifest {
      self.outPath = root;
      files.shared = "${root}/../outside.nix.age";
    };
    expectedError = {
      type = "ThrownError";
      msg = "manifest path /example/outside\\.nix\\.age is outside flake root";
    };
  };

  testManifestNormalizesStringLocations = {
    expr =
      (shieldsLib.mkManifest {
        self.outPath = "${root}/.";
        files.shared = "${root}/shields/nested/../shared.nix.age";
      }).files.shared;
    expected = "shields/shared.nix.age";
  };
}
