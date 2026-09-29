/*
  The option tree driven through evalModules without the builtin
  present (the pure tier of the spec's testing decisions). Every case
  is decided before importShield reaches the builtin: a missing file
  and an empty identity list fail on their own, so the module's wiring
  of files to values is observable without a plugin build.
*/
{ lib, runCommand }:
let
  inherit (builtins) deepSeq tryEval;
  inherit (lib)
    attrNames
    concatStringsSep
    evalModules
    filterAttrs
    length
    ;

  cases = {
    defaults =
      let
        cfg = evalShields [ ];
      in
      cfg.masterIdentities == [ ] && cfg.files == { } && cfg.values == { };

    identitiesRejectRelativeStrings =
      fails
        (withShields { masterIdentities = [ "throwaway.txt" ]; }).masterIdentities;
    identitiesRejectSingleValue =
      fails
        (withShields { masterIdentities = /identity.txt; }).masterIdentities;
    filesRejectNonPaths = fails (withShields { files.facts = 42; }).files;

    dirRequiredWhenReferenced = fails (evalShields [ ]).dir;
    dirRejectsRelativeStrings = fails (withShields { dir = "shields"; }).dir;
    dirReadsBack = (withShields { dir = /srv/shields; }).dir == /srv/shields;
    filesBuiltFromDir = (evalShields [ wiredFromDir ]).files.facts == /srv/shields/alpha.nix.age;

    valuesReadOnly = fails (withShields { values.facts = { }; }).values;
    # Names are listable without decrypting anything.
    valuesKeyedByFiles = attrNames (evalShields [ missingFile ]).values == [ "facts" ];
    valuesFailWithoutFile = fails (evalShields [ missingFile ]).values.facts;
    valuesFailWithoutIdentity = fails (evalShields [ existingFile ]).values.facts;
  };

  evalShields =
    modules: (evalModules { modules = [ ../../nixos/module.nix ] ++ modules; }).config.age.shields;

  withShields = settings: evalShields [ { age.shields = settings; } ];

  fails = value: !(tryEval (deepSeq value value)).success;

  # The consumer's own wiring builds file locations from dir.
  wiredFromDir =
    { config, ... }:
    {
      age.shields.dir = /srv/shields;
      age.shields.files.facts = config.age.shields.dir + "/alpha.nix.age";
    };

  missingFile.age.shields.files.facts = /srv/shields/missing.nix.age;
  # The example's shield exists, so this case gets past the file check.
  existingFile.age.shields.files.facts = ../../examples/consumer/shields/alpha.nix.age;

  failed = attrNames (filterAttrs (_: ok: !ok) cases);
in
runCommand "nixos-shields-nixos-module"
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
