/*
  composeBuiltins — merges the kit's builtins with a consumer's entries.
  The bundle that mkNix builds imports this file beside its copies of
  the kit's file and the entries, so nix-plugins' allow-list, which
  covers the bundle alone, admits every file it reads.

  Inputs:
    kit: the kit's extra-builtins function.
    extras: the consumer's entries in order, each { name, builtins }:
      `name` names the entry in failures, and `builtins` is its
      extra-builtins function.
    args: the arguments nix-plugins supplies, handed to each function.

  Returns the merged builtins.
*/
kit: extras: args:
let
  inherit (builtins)
    attrNames
    filter
    foldl'
    head
    listToAttrs
    ;

  kitBuiltins = kit args;

  /*
    Each step adds one entry's builtins and records the entry that
    defines each name. foldl' forces every step, so a failing entry
    fails the merged set, whichever builtin is read.
  */
  add =
    merged: extra:
    let
      entryBuiltins = extra.builtins args;
      names = attrNames entryBuiltins;
      reserved = filter (name: kitBuiltins ? ${name}) names;
      taken = filter (name: merged.owners ? ${name}) names;
    in
    if reserved != [ ] then
      throw "nixos-shields: extra builtins ${extra.name} define ${head reserved}, which the kit reserves"
    else if taken != [ ] then
      throw "nixos-shields: extra builtins ${merged.owners.${head taken}} and ${extra.name} both define ${head taken}"
    else
      {
        builtins = merged.builtins // entryBuiltins;
        owners = merged.owners // listToAttrs (map (name: nameValuePair name extra.name) names);
      };

  nameValuePair = name: value: { inherit name value; };

  extraBuiltins =
    (foldl' add {
      builtins = { };
      owners = { };
    } extras).builtins;
in
extraBuiltins // kitBuiltins
