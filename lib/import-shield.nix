/*
  importShield — decrypts a shield file and returns the Nix value it
  holds. The modules read shields only through this function, which
  names a missing file, an empty identity list, or a Nix without the
  builtin before decrypting. Reading needs the wrapped Nix from mkNix.

  Inputs:
    identities: the master identities, any one of which can decrypt the
      shield, in the forms age.shields.masterIdentities accepts: a path,
      an absolute path string, or { identity, pubkey }. Only the
      identity files are used; a public key matters only to encryption.
    file: the shield file, a path whose name ends in `.nix.age`.

  Returns the value of the decrypted Nix expression.

  Example:
    importShield [ ./master-ids/yubikey-1.pub ] ./shields/beta.nix.age
*/
identities: file:
let
  coerceMasterIdentity = import ./coerce-master-identity.nix;

  # The builtin takes paths and absolute path strings, so a key outside
  # the flake is named in place, never copied into the store.
  identityOf = entry: (coerceMasterIdentity entry).identity;

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
  extraBuiltins.importShield (map identityOf identities) file
