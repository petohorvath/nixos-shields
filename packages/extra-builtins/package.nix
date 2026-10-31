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
  extraBuiltins ? [ ],
}:
let
  kit = replaceVars ./extra-builtins.nix { decrypt = lib.getExe decrypt; };

  # The name a failure gives the entry.
  nameOf = entry: if lib.isDerivation entry then entry.name else baseNameOf entry;

  copyEntry = index: entry: ''
    cp -rL ${lib.escapeShellArg "${entry}"} "$out/extras/${toString index}"
  '';
in
runCommand "nixos-shields-extra-builtins"
  {
    names = builtins.toJSON (map nameOf extraBuiltins);
    passAsFile = [ "names" ];
  }
  ''
    mkdir -p "$out/extras"
    cp ${./bundle.nix} "$out/default.nix"
    cp ${./compose.nix} "$out/compose.nix"
    cp ${kit} "$out/kit.nix"
    cp "$namesPath" "$out/extras.json"
    ${lib.concatStrings (lib.imap0 copyEntry extraBuiltins)}
  ''
