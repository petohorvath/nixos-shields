/*
  mkExtraBuiltinsFile — builds the kit's extra-builtins file, which
  defines importShield. A consumer with builtins of its own imports the
  result from its own extra-builtins file and hands the combined file
  to mkNix as `extraBuiltinsFile`.

  Inputs:
    pkgs: the package set that builds the decrypt script.

  Returns a derivation whose output is the extra-builtins file.
*/
{ pkgs }:
pkgs.callPackage ../packages/extra-builtins/package.nix {
  decrypt = pkgs.callPackage ../packages/decrypt/package.nix { };
}
