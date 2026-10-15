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
    masterIdentities = [
      {
        identity = "master-identities/throwaway.txt";
        pubkey = null;
      }
    ];
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
  # anywhere, in any form, appears once, with the public key any of its
  # entries pairs it with.
  testManifestCombinesConfigurationIdentities = {
    expr =
      (shieldsLib.mkManifest {
        self.outPath = flakeRoot;
        configurations = {
          beta.config.age.shields.masterIdentities = [
            betaIdentityPath
            {
              identity = alphaIdentityPath;
              pubkey = "age1alpha";
            }
          ];
          alpha.config.age.shields.masterIdentities = [
            (toString alphaIdentityPath)
            { identity = identityPath; }
            {
              identity = alphaIdentityPath;
              pubkey = null;
            }
          ];
          unshielded.config.networking.hostName = "unshielded";
        };
      }).masterIdentities;
    expected = [
      {
        identity = "master-identities/alpha.txt";
        pubkey = "age1alpha";
      }
      {
        identity = "master-identities/throwaway.txt";
        pubkey = null;
      }
      {
        identity = "master-identities/beta.txt";
        pubkey = null;
      }
    ];
  };

  testManifestRejectsConflictingPublicKeys = {
    expr =
      (shieldsLib.mkManifest {
        self.outPath = flakeRoot;
        configurations = {
          alpha.config.age.shields.masterIdentities = [
            {
              identity = alphaIdentityPath;
              pubkey = "age1first";
            }
          ];
          beta.config.age.shields.masterIdentities = [
            {
              identity = toString alphaIdentityPath;
              pubkey = "age1first";
            }
            {
              identity = alphaIdentityPath;
              pubkey = "age1second";
            }
          ];
        };
      }).masterIdentities;
    expectedError = {
      type = "ThrownError";
      msg = "master identity master-identities/alpha\\.txt is paired with different public keys: age1first and age1second";
    };
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

  # An identity outside the flake root, such as a plain key under the
  # home directory, keeps its normalized absolute location, so the tool
  # finds it from any working directory; inside ones become relative.
  testManifestKeepsOutsideIdentitiesAbsolute = {
    expr =
      (shieldsLib.mkManifest {
        self.outPath = root;
        configurations = {
          alpha.config.age.shields.masterIdentities = [
            "${root}/../outside.txt"
            identityPath
          ];
          beta.config.age.shields.masterIdentities = [
            {
              identity = /home/user/.config/age/../age/key.txt;
              pubkey = "age1home";
            }
            "/example/outside.txt"
          ];
        };
      }).masterIdentities;
    expected = [
      {
        identity = "/example/outside.txt";
        pubkey = null;
      }
      {
        identity = "master-identities/throwaway.txt";
        pubkey = null;
      }
      {
        identity = "/home/user/.config/age/key.txt";
        pubkey = "age1home";
      }
    ];
  };

  testManifestRejectsRelativeIdentityString = {
    expr =
      (shieldsLib.mkManifest {
        self.outPath = root;
        configurations.alpha.config.age.shields.masterIdentities = [ "master-identities/relative.txt" ];
      }).masterIdentities;
    expectedError = {
      type = "ThrownError";
      msg = "master identity master-identities/relative\\.txt must be a path or an absolute path string";
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
      masterIdentities = [
        {
          identity = "master-identities/throwaway.txt";
          pubkey = null;
        }
      ];
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
