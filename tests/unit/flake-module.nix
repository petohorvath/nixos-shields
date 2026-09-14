/*
  The manifest builder and flake-parts option tree, evaluated without
  the builtin. Only public outputs are read: the manifest and options
  of configurations importing the pre-configured NixOS module.
*/
{
  lib,
  runCommand,
  flakeParts,
}:
let
  inherit (builtins) deepSeq tryEval;
  inherit (lib)
    attrNames
    concatStringsSep
    evalModules
    filterAttrs
    length
    ;

  shieldsLib = import ../../lib;

  evalFlake =
    modules:
    flakeParts.lib.evalFlakeModule { inputs.self.outPath = /nix/store/example-source; } {
      imports = [ ../../modules/flake.nix ] ++ modules;
    };

  configured = evalFlake [
    {
      shields = {
        dir = /nix/store/example-source/shields;
        masterIdentities = [ /nix/store/example-source/master-identities/throwaway.txt ];
      };
    }
  ];

  evalConfiguration =
    modules:
    (evalModules {
      modules = [ configured.config.shields.nixosModule ] ++ modules;
    }).config.age.shields;

  withShields = settings: (evalFlake [ { shields = settings; } ]).config.shields;

  fails = value: !(tryEval (deepSeq value value)).success;

  cases = {
    manifestRelativeLocations =
      shieldsLib.mkManifest {
        self.outPath = /nix/store/example-source;
        masterIdentities = [ /nix/store/example-source/master-identities/throwaway.txt ];
        files.shared = /nix/store/example-source/shields/shared.nix.age;
        configurations.alpha.config.age.shields.files.facts =
          /nix/store/example-source/shields/alpha.nix.age;
      } == {
        masterIdentities = [ "master-identities/throwaway.txt" ];
        files.shared = "shields/shared.nix.age";
        configurations.alpha.files.facts = "shields/alpha.nix.age";
      };

    nixosModuleInheritsDefaults =
      let
        cfg = evalConfiguration [ ];
      in
      cfg.dir == /nix/store/example-source/shields
      && cfg.masterIdentities == [ /nix/store/example-source/master-identities/throwaway.txt ]
      && cfg.files == { }
      && cfg.values == { };

    flakePublishesManifest =
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
      ]).config.flake.shields == {
        masterIdentities = [ "master-identities/throwaway.txt" ];
        files.shared = "shields/shared.nix.age";
        configurations.alpha.files.facts = "shields/alpha.nix.age";
      };

    valuesKeyedByFiles =
      attrNames
        (withShields {
          files.shared = /nix/store/example-source/shields/shared.nix.age;
        }).values == [ "shared" ];

    defaults =
      let
        cfg = withShields { };
      in
      cfg.masterIdentities == [ ] && cfg.files == { } && cfg.values == { } && cfg.configurations == { };

    dirRequiredWhenReferenced = fails (withShields { }).dir;
    dirRejectsRelativeStrings = fails (withShields { dir = "shields"; }).dir;
    identitiesRejectNonPaths = fails (withShields { masterIdentities = [ 42 ]; }).masterIdentities;
    filesRejectNonPaths = fails (withShields { files.shared = 42; }).files;
    valuesReadOnly = fails (withShields { values.shared = { }; }).values;
    nixosModuleReadOnly = fails (withShields { nixosModule = { }; }).nixosModule;

    valuesFailWithoutFile =
      fails
        (withShields {
          files.shared = /nix/store/example-source/shields/missing.nix.age;
        }).values.shared;
    valuesFailWithoutIdentity =
      fails
        (withShields {
          files.shared = ../../examples/consumer/shields/alpha.nix.age;
        }).values.shared;

    nixosModuleDefaultsOverridden =
      let
        cfg = evalConfiguration [
          {
            age.shields = {
              dir = /srv/another-directory;
              masterIdentities = [ /srv/another-identity.txt ];
            };
          }
        ];
      in
      cfg.dir == /srv/another-directory && cfg.masterIdentities == [ /srv/another-identity.txt ];

    nixosModuleIdentitiesCanBeCleared =
      (evalConfiguration [
        { age.shields.masterIdentities = [ ]; }
      ]).masterIdentities == [ ];

    nixosModuleWiresFilesFromDir =
      (evalConfiguration [
        ({ config, ... }: { age.shields.files.facts = config.age.shields.dir + "/alpha.nix.age"; })
      ]).files.facts == /nix/store/example-source/shields/alpha.nix.age;

    configurationsCanUseAnotherOutput =
      (evalFlake [
        {
          flake.nixosConfigurations.unused = throw "the default configurations must not be evaluated";
          shields.configurations.beta.config.age.shields.files.facts =
            /nix/store/example-source/shields/beta.nix.age;
        }
      ]).config.flake.shields.configurations == {
        beta.files.facts = "shields/beta.nix.age";
      };

    manifestDefaults =
      shieldsLib.mkManifest { self.outPath = /nix/store/example-source; } == {
        masterIdentities = [ ];
        files = { };
        configurations = { };
      };

    manifestIncludesUnshieldedConfigurations =
      (shieldsLib.mkManifest {
        self.outPath = /nix/store/example-source;
        configurations.unshielded.config.networking.hostName = "unshielded";
      }).configurations == {
        unshielded.files = { };
      };

    manifestAcceptsAbsoluteStrings =
      (shieldsLib.mkManifest {
        self.outPath = "/nix/store/example-source";
        masterIdentities = [ "/nix/store/example-source/master-identities/throwaway.txt" ];
        files.shared = "/nix/store/example-source/shields/shared.nix.age";
      }) == {
        masterIdentities = [ "master-identities/throwaway.txt" ];
        files.shared = "shields/shared.nix.age";
        configurations = { };
      };

    manifestRejectsOtherRoots = fails (
      shieldsLib.mkManifest {
        self.outPath = /nix/store/example-source;
        files.shared = /nix/store/example-source-other/shields/shared.nix.age;
      }
    );

    manifestRejectsIdentityOutsideRoot = fails (
      shieldsLib.mkManifest {
        self.outPath = /nix/store/example-source;
        masterIdentities = [ /srv/identity.txt ];
      }
    );

    manifestRejectsEscapingString = fails (
      shieldsLib.mkManifest {
        self.outPath = "/nix/store/example-source";
        files.shared = "/nix/store/example-source/../outside.nix.age";
      }
    );

    manifestNormalizesStringLocations =
      (shieldsLib.mkManifest {
        self.outPath = "/nix/store/example-source/.";
        files.shared = "/nix/store/example-source/shields/nested/../shared.nix.age";
      }).files.shared == "shields/shared.nix.age";
  };

  failed = attrNames (filterAttrs (_: ok: !ok) cases);
in
runCommand "nixos-shields-flake-module"
  {
    failed = concatStringsSep " " failed;
    total = toString (length (attrNames cases));
  }
  ''
    if [[ -n $failed ]]; then
      echo "FAIL: $failed" >&2
      exit 1
    fi
    echo "$total cases passed"
    touch "$out"
  ''
