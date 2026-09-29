/*
  mkExtraBuiltinsFile — builds the kit's extra-builtins file for a
  package set. A consumer with builtins of its own imports the result
  from its own extra-builtins file and hands the combined file to mkNix
  as `extraBuiltinsFile`.
*/
{ pkgs }:
pkgs.callPackage ../packages/extra-builtins/package.nix {
  decrypt = pkgs.callPackage ../packages/decrypt/package.nix { };
}
