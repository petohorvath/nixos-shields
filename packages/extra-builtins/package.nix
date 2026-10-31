/*
  The extra-builtins bundle the wrapped Nix loads: one directory holding
  the kit's builtins, with the cache script's store path baked in, and a
  copy of each consumer entry. nix-plugins admits only the configured
  path and what lies below it in pure evaluation, so the entries are
  copied in, never linked or imported from another store path.

  extraBuiltins: the consumer's entries, each a path or a derivation
    holding an extra-builtins function, as a file or as a directory with
    a default.nix.
*/
{
  lib,
  replaceVars,
  runCommand,
  decrypt,
  extraBuiltins,
}:
let
  kit = replaceVars ./extra-builtins.nix { decrypt = lib.getExe decrypt; };

  # A string without context names no store path, so the copy could not
  # track the file's content.
  isEntry =
    entry:
    builtins.isPath entry
    || lib.isDerivation entry
    || (builtins.isString entry && builtins.hasContext entry);

  checkEntry =
    entry:
    isEntry entry
    || throw "nixos-shields: extra builtins entry ${toString entry} must be a path or a derivation";

  # What bundle.nix reads of each entry: the name a failure gives it,
  # and its copy's location in the bundle.
  extraOf = index: entry: {
    name = if lib.isDerivation entry then entry.name else baseNameOf entry;
    file = "extras/${toString index}";
  };

  extras = lib.imap0 extraOf extraBuiltins;

  copyCommand = entry: extra: ''
    cp -rL ${lib.escapeShellArg "${entry}"} "$out/${extra.file}"
  '';
in
assert
  builtins.isList extraBuiltins
  || throw "nixos-shields: extraBuiltins must be a list of paths or derivations";
assert builtins.all checkEntry extraBuiltins;
runCommand "nixos-shields-extra-builtins"
  {
    extras = builtins.toJSON extras;
    passAsFile = [ "extras" ];
  }
  ''
    mkdir -p "$out/extras"
    cp ${./bundle.nix} "$out/default.nix"
    cp ${./compose.nix} "$out/compose.nix"
    cp ${kit} "$out/kit.nix"
    cp "$extrasPath" "$out/extras.json"
    ${lib.concatStrings (lib.zipListsWith copyCommand extraBuiltins extras)}
  ''
