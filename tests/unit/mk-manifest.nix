# lib.mkManifest, called directly as a plain flake would.
{ fixtures, shieldsLib, ... }:
let
  inherit (fixtures)
    exampleConfigurations
    exampleManifest
    flakeRoot
    stubFlakeRoot
    ;
  root = toString flakeRoot;
  identityPath = flakeRoot + "/master-identities/throwaway.txt";
  alphaIdentityPath = flakeRoot + "/master-identities/alpha.txt";
  betaIdentityPath = flakeRoot + "/master-identities/beta.txt";
  sharedShieldPath = flakeRoot + "/shields/shared.nix.age";

  stubPath = name: stubFlakeRoot + "/master-identities/${name}";

  # The manifest identities of one configuration in the stub flake.
  stubManifestIdentities =
    masterIdentities:
    (shieldsLib.mkManifest {
      self.outPath = stubFlakeRoot;
      configurations.alpha.config.age.shields = { inherit masterIdentities; };
    }).masterIdentities;
in
{
  testRelativeLocations = {
    expr = shieldsLib.mkManifest {
      self.outPath = flakeRoot;
      configurations = exampleConfigurations;
    };
    expected = exampleManifest;
  };

  # Each configuration's list in name order; an identity repeated
  # anywhere, in any form, appears once, with the public key any of its
  # entries pairs it with.
  testCombinesConfigurationIdentities = {
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

  # Each configuration's list in name order, each entry once. A recipients
  # file inside the root, as a path or a string, becomes relative to it;
  # one outside stays absolute. Other strings are public keys.
  testCombinesExtraEncryptionPubkeys = {
    expr =
      (shieldsLib.mkManifest {
        self.outPath = root;
        configurations = {
          beta.config.age.shields.extraEncryptionPubkeys = [
            "age1beta"
            "${root}/recipients/../recipients/team.txt"
            "age1backup"
            "/home/user/.config/age/recipients.txt"
          ];
          alpha.config.age.shields.extraEncryptionPubkeys = [
            "age1backup"
            (flakeRoot + "/recipients/team.txt")
            /home/user/.config/age/../age/recipients.txt
          ];
          unshielded.config.networking.hostName = "unshielded";
        };
      }).extraEncryptionPubkeys;
    expected = [
      { pubkey = "age1backup"; }
      { recipientsFile = "recipients/team.txt"; }
      { recipientsFile = "/home/user/.config/age/recipients.txt"; }
      { pubkey = "age1beta"; }
    ];
  };

  testRejectsConflictingPublicKeys = {
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

  # The manifest reads no identity file, so an undeclared stub's public
  # key is null, and a binary identity, which Nix cannot read, is fine.
  testLeavesUndeclaredStubPubkeyNull = {
    expr = stubManifestIdentities [
      (stubPath "yubikey.txt")
      (stubPath "binary-passphrase-protected.age")
    ];
    expected = [
      {
        identity = "master-identities/yubikey.txt";
        pubkey = null;
      }
      {
        identity = "master-identities/binary-passphrase-protected.age";
        pubkey = null;
      }
    ];
  };

  testRejectsMasterIdentitiesArgument = {
    expr = shieldsLib.mkManifest {
      self.outPath = flakeRoot;
      masterIdentities = [ identityPath ];
    };
    expectedError.msg = "unexpected argument 'masterIdentities'";
  };

  testRejectsFilesArgument = {
    expr = shieldsLib.mkManifest {
      self.outPath = flakeRoot;
      files.shared = sharedShieldPath;
    };
    expectedError.msg = "unexpected argument 'files'";
  };

  # An identity outside the flake root, such as a plain key under the
  # home directory, keeps its normalized absolute location, so the tool
  # finds it from any working directory; inside ones become relative.
  testKeepsOutsideIdentitiesAbsolute = {
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

  testRejectsRelativeIdentityString = {
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

  # Also covers the default of the omitted argument.
  testIncludesUnshieldedConfigurations = {
    expr = shieldsLib.mkManifest {
      self.outPath = flakeRoot;
      configurations.unshielded.config.networking.hostName = "unshielded";
    };
    expected = {
      masterIdentities = [ ];
      extraEncryptionPubkeys = [ ];
      configurations.unshielded.files = { };
    };
  };

  testAcceptsAbsoluteStrings = {
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
      extraEncryptionPubkeys = [ ];
      configurations.alpha.files.shared = "shields/shared.nix.age";
    };
  };

  testRejectsEscapingString = {
    expr = shieldsLib.mkManifest {
      self.outPath = root;
      configurations.alpha.config.age.shields.files.shared = "${root}/../outside.nix.age";
    };
    expectedError = {
      type = "ThrownError";
      msg = "manifest path /example/outside\\.nix\\.age is outside flake root ${root}$";
    };
  };

  testNormalizesStringLocations = {
    expr =
      (shieldsLib.mkManifest {
        self.outPath = "${root}/.";
        configurations.alpha.config.age.shields.files.shared = "${root}/shields/nested/../shared.nix.age";
      }).configurations.alpha.files.shared;
    expected = "shields/shared.nix.age";
  };
}
