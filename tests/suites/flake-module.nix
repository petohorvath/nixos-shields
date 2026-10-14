/*
  The manifest builder and flake-parts option tree, evaluated without
  the builtin. Only public outputs are read: the manifest and the
  options of the flake-parts module.
*/
{
  evalFlakeModule,
  flakeRoot,
  shieldsLib,
  ...
}:
let
  root = toString flakeRoot;
  shieldsDir = flakeRoot + "/shields";
  identityPath = flakeRoot + "/master-identities/throwaway.txt";
  alphaIdentityPath = flakeRoot + "/master-identities/alpha.txt";
  betaIdentityPath = flakeRoot + "/master-identities/beta.txt";
  sharedShieldPath = shieldsDir + "/shared.nix.age";
  alphaShieldPath = shieldsDir + "/alpha.nix.age";

  # Two configurations that declare one shield file between them.
  exampleConfigurations = {
    alpha.config.age.shields = {
      masterIdentities = [ identityPath ];
      files = {
        facts = alphaShieldPath;
        shared = sharedShieldPath;
      };
      values = throw "the manifest must not decrypt shields";
    };
    beta.config.age.shields = {
      masterIdentities = [ identityPath ];
      files.shared = sharedShieldPath;
    };
  };

  exampleManifest = {
    masterIdentities = [ "master-identities/throwaway.txt" ];
    configurations = {
      alpha.files = {
        facts = "shields/alpha.nix.age";
        shared = "shields/shared.nix.age";
      };
      beta.files.shared = "shields/shared.nix.age";
    };
  };
in
{
  testManifestRelativeLocations = {
    expr = shieldsLib.mkManifest {
      self.outPath = flakeRoot;
      configurations = exampleConfigurations;
    };
    expected = exampleManifest;
  };

  # Each configuration's list in name order; an identity repeated
  # anywhere, in any form, appears once.
  testManifestCombinesConfigurationIdentities = {
    expr =
      (shieldsLib.mkManifest {
        self.outPath = flakeRoot;
        configurations = {
          beta.config.age.shields.masterIdentities = [
            betaIdentityPath
            alphaIdentityPath
          ];
          alpha.config.age.shields.masterIdentities = [
            (toString alphaIdentityPath)
            identityPath
            alphaIdentityPath
          ];
          unshielded.config.networking.hostName = "unshielded";
        };
      }).masterIdentities;
    expected = [
      "master-identities/alpha.txt"
      "master-identities/throwaway.txt"
      "master-identities/beta.txt"
    ];
  };

  testManifestRejectsMasterIdentitiesArgument = {
    expr = shieldsLib.mkManifest {
      self.outPath = flakeRoot;
      masterIdentities = [ identityPath ];
    };
    expectedError.msg = "unexpected argument 'masterIdentities'";
  };

  testManifestRejectsFilesArgument = {
    expr = shieldsLib.mkManifest {
      self.outPath = flakeRoot;
      files.shared = sharedShieldPath;
    };
    expectedError.msg = "unexpected argument 'files'";
  };

  testManifestRejectsEscapingConfigurationIdentity = {
    expr =
      (shieldsLib.mkManifest {
        self.outPath = root;
        configurations.alpha.config.age.shields.masterIdentities = [ "${root}/../outside.txt" ];
      }).masterIdentities;
    expectedError = {
      type = "ThrownError";
      msg = "manifest path /example/outside\\.txt is outside flake root ${root}$";
    };
  };

  testFlakePublishesManifest = {
    expr = (evalFlakeModule [ { flake.nixosConfigurations = exampleConfigurations; } ]).flake.shields;
    expected = exampleManifest;
  };

  # The module declares no shields or identities of its own.
  testFlakeDeclaresOnlyConfigurations = {
    expr = builtins.attrNames (evalFlakeModule [ ]).shields;
    expected = [ "configurations" ];
  };

  testDefaults = {
    expr = {
      inherit ((evalFlakeModule [ ]).shields) configurations;
      inherit ((evalFlakeModule [ ]).flake) shields;
    };
    expected = {
      configurations = { };
      shields = {
        masterIdentities = [ ];
        configurations = { };
      };
    };
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

  # Also covers the default of the omitted argument.
  testManifestIncludesUnshieldedConfigurations = {
    expr = shieldsLib.mkManifest {
      self.outPath = flakeRoot;
      configurations.unshielded.config.networking.hostName = "unshielded";
    };
    expected = {
      masterIdentities = [ ];
      configurations.unshielded.files = { };
    };
  };

  testManifestAcceptsAbsoluteStrings = {
    expr = shieldsLib.mkManifest {
      self.outPath = root;
      configurations.alpha.config.age.shields = {
        masterIdentities = [ (toString identityPath) ];
        files.shared = toString sharedShieldPath;
      };
    };
    expected = {
      masterIdentities = [ "master-identities/throwaway.txt" ];
      configurations.alpha.files.shared = "shields/shared.nix.age";
    };
  };

  testManifestRejectsEscapingString = {
    expr = shieldsLib.mkManifest {
      self.outPath = root;
      configurations.alpha.config.age.shields.files.shared = "${root}/../outside.nix.age";
    };
    expectedError = {
      type = "ThrownError";
      msg = "manifest path /example/outside\\.nix\\.age is outside flake root ${root}$";
    };
  };

  testManifestNormalizesStringLocations = {
    expr =
      (shieldsLib.mkManifest {
        self.outPath = "${root}/.";
        configurations.alpha.config.age.shields.files.shared = "${root}/shields/nested/../shared.nix.age";
      }).configurations.alpha.files.shared;
    expected = "shields/shared.nix.age";
  };
}
