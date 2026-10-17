# The flake-parts option tree, evaluated without the builtin. Only the
# module's options and the manifest it publishes are read.
{ fixtures, helpers, ... }:
let
  inherit (fixtures) exampleConfigurations exampleManifest flakeRoot;
  inherit (helpers) evalFlakeModule;
  shieldsDir = flakeRoot + "/shields";
in
{
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
        extraEncryptionPubkeys = [ ];
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
}
