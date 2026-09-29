# Bakes the cache script's store path into the extra-builtins file.
{
  lib,
  replaceVars,
  decrypt,
}:
replaceVars ./extra-builtins.nix { decrypt = lib.getExe decrypt; }
