/*
  composeBuiltins — merges the kit's builtins with a consumer's entries.
  The bundle that mkNix builds imports this file beside its copies of
  the kit's file and the entries, so nix-plugins' allow-list, which
  covers the bundle alone, admits every file it reads.

  Inputs:
    kit: the kit's extra-builtins function.
    extras: the consumer's entries in order, each { name, builtins }:
      `name` names the entry in failures, beside its position, and
      `builtins` is its extra-builtins function.
    args: the arguments nix-plugins supplies, handed to each function.

  Returns the merged builtins.
*/
kit: extras: args:
let
  inherit (builtins)
    attrNames
    elemAt
    filter
    foldl'
    genList
    head
    length
    listToAttrs
    ;

  kitBuiltins = kit args;

  # Entries can share a name, so a failure gives the entry's position.
  labelled = genList (
    index:
    let
      extra = elemAt extras index;
    in
    extra // { label = "${toString (index + 1)} (${extra.name})"; }
  ) (length extras);

  # Adds an entry's builtins and records it as the owner of each name.
  # foldl' forces every step, so any failing entry fails the merged set.
  addEntry =
    merged: extra:
    let
      entryBuiltins = extra.builtins args;
      names = attrNames entryBuiltins;
      reserved = filter (name: kitBuiltins ? ${name}) names;
      taken = filter (name: merged.owners ? ${name}) names;
    in
    if reserved != [ ] then
      throw "nixos-shields: extra builtins entry ${extra.label} defines ${head reserved}, which the kit reserves"
    else if taken != [ ] then
      throw "nixos-shields: extra builtins entries ${merged.owners.${head taken}} and ${extra.label} both define ${head taken}"
    else
      {
        builtins = merged.builtins // entryBuiltins;
        owners =
          merged.owners
          // listToAttrs (
            map (name: {
              inherit name;
              value = extra.label;
            }) names
          );
      };

  consumerBuiltins =
    (foldl' addEntry {
      builtins = { };
      owners = { };
    } labelled).builtins;
in
consumerBuiltins // kitBuiltins
