/*
  importShield — decrypts a shield file with the master identities and
  returns the Nix value it holds. The only entry point modules use; it
  needs the wrapped Nix (mkNix) so the importShield builtin is loaded.

  Example:
    importShield [ ./master-ids/yubikey-1.pub ] ./shields/beta.nix.age
*/
identities: file:
let
  extraBuiltins = builtins.extraBuiltins or null;
  # A loaded plugin with no extra-builtins file evaluates to null.
  hasBuiltin = builtins.isAttrs extraBuiltins && extraBuiltins ? importShield;

  # toString, unlike interpolation, names the path without copying it.
  location = toString file;
  missingFile = "nixos-shields: shield file ${location} does not exist";
  noIdentity = "nixos-shields: no master identity configured; cannot decrypt ${location}";
  noBuiltin = "nixos-shields: importShield builtin not loaded; use the wrapped Nix from lib.mkNix";
in
if !builtins.pathExists file then
  throw missingFile
else if identities == [ ] then
  throw noIdentity
else if !hasBuiltin then
  throw noBuiltin
else
  extraBuiltins.importShield identities file
