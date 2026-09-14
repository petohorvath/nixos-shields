/*
  The kit's extra-builtins file, loaded by nix-plugins on every
  invocation of the wrapped Nix. `@decrypt@` becomes the cache script's
  store path at build time. A consumer composes it with other builtins
  by importing the built file and merging:

    let kit = nixos-shields.lib.mkExtraBuiltinsFile { inherit pkgs; };
    in args: (import kit args) // { mine = ...; }
*/
{ exec, ... }:
let
  inherit (builtins)
    all
    isList
    isPath
    pathExists
    stringLength
    substring
    ;

  # nixpkgs lib is not in scope here, so the predicates are hand-rolled.
  isPathList = list: isList list && all isPath list;

  hasSuffix =
    suffix: string:
    let
      length = stringLength string;
      suffixLength = stringLength suffix;
      start = length - suffixLength;
    in
    length >= suffixLength && substring start suffixLength string == suffix;

  badIdentities = "importShield: the master identities must be a list of paths";
  badFile = file: "importShield: shield file must be an existing path: ${toString file}";
  badSuffix = file: "importShield: shield file name must end in .nix.age: ${toString file}";
in
{
  /*
    Decrypts a shield file with the master identities and returns the
    Nix value it holds. The checks are repeated from lib.importShield
    because the builtin is callable on its own. The suffix is checked
    on the base name: string operations on the path itself would copy
    the shield into the store.
  */
  importShield =
    identities: file:
    assert isPathList identities || throw badIdentities;
    assert (isPath file && pathExists file) || throw (badFile file);
    assert hasSuffix ".nix.age" (baseNameOf file) || throw (badSuffix file);
    exec (
      [
        "@decrypt@"
        file
      ]
      ++ identities
    );
}
