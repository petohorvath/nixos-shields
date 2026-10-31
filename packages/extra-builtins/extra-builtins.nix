/*
  The kit's builtins, loaded by nix-plugins on every invocation of the
  wrapped Nix as kit.nix of the extra-builtins bundle, which merges them
  with a consumer's own through compose.nix. `@decrypt@` becomes the
  cache script's store path at build time.
*/
{ exec, ... }:
let
  inherit (builtins)
    all
    isList
    isPath
    isString
    pathExists
    stringLength
    substring
    ;

  # nixpkgs lib is not in scope here, so the predicates are hand-rolled.
  # An identity outside the flake is an absolute path string, as a shield
  # file can be; exec passes paths and strings alike without copying them
  # into the store.
  isLocation = location: isPath location || (isString location && substring 0 1 location == "/");
  isIdentityList = list: isList list && all isLocation list;

  hasSuffix =
    suffix: string:
    let
      length = stringLength string;
      suffixLength = stringLength suffix;
      start = length - suffixLength;
    in
    length >= suffixLength && substring start suffixLength string == suffix;

  noIdentity = file: "nixos-shields: no master identity configured; cannot decrypt ${toString file}";
  badIdentities = "nixos-shields: the master identities must be a list of paths or absolute path strings";
  badFileType =
    file: "nixos-shields: shield file ${toString file} must be a path or an absolute path string";
  badSuffix = file: "nixos-shields: shield file name must end in .nix.age: ${toString file}";
  missingFile = file: "nixos-shields: shield file ${toString file} does not exist";
in
{
  /*
    Decrypts a shield file with the master identities and returns the
    Nix value it holds. The builtin owns every check on its arguments,
    so it fails the same way whether called directly or through
    lib.importShield. The suffix is checked on the base name: string
    operations on the path itself would copy the shield into the store.
  */
  importShield =
    identities: file:
    assert identities != [ ] || throw (noIdentity file);
    assert isIdentityList identities || throw badIdentities;
    assert isLocation file || throw (badFileType file);
    assert hasSuffix ".nix.age" (baseNameOf file) || throw (badSuffix file);
    assert pathExists file || throw (missingFile file);
    exec (
      [
        "@decrypt@"
        file
      ]
      ++ identities
    );
}
