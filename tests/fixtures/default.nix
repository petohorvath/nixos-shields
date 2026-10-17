# Test data shared by the suites.
let
  # A consumer's flake root. Only its path is read; it need not exist.
  flakeRoot = /example/flake;

  identityPath = flakeRoot + "/master-identities/throwaway.txt";
  sharedShieldPath = flakeRoot + "/shields/shared.nix.age";
  alphaShieldPath = flakeRoot + "/shields/alpha.nix.age";
in
{
  inherit flakeRoot;

  # The example's shield exists, so reading it gets past the file check.
  existingShieldPath = ../../examples/consumer/shields/alpha.nix.age;

  # A flake root holding a YubiKey identity stub and a binary
  # passphrase-protected identity.
  stubFlakeRoot = ./flake;

  # Two configurations in flakeRoot that declare one shield file between
  # them.
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

  # The manifest of exampleConfigurations.
  exampleManifest = {
    masterIdentities = [
      {
        identity = "master-identities/throwaway.txt";
        pubkey = null;
      }
    ];
    extraEncryptionPubkeys = [ ];
    configurations = {
      alpha.files = {
        facts = "shields/alpha.nix.age";
        shared = "shields/shared.nix.age";
      };
      beta.files.shared = "shields/shared.nix.age";
    };
  };
}
