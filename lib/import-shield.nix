/*
  importShield — decrypts a shield file and returns the Nix value it
  holds. The modules read shields only through this function, which
  hands the identity files to the builtin. The builtin checks both
  arguments; this function names a Nix without the builtin. Reading
  needs the wrapped Nix from mkNix.

  Inputs:
    extraBuiltins: the running Nix's builtins.extraBuiltins, or null
      without one. lib and the NixOS module apply it, so the public
      importShield takes the two arguments below.
    identities: the master identities, any one of which can decrypt the
      shield, in the forms age.shields.masterIdentities accepts: a path,
      an absolute path string, or { identity, pubkey }. Only the
      identity files are used; a public key matters only to encryption.
    file: the shield file, a path or an absolute path string whose name
      ends in `.nix.age`.

  Returns the value of the decrypted Nix expression.

  Example:
    importShield [ ./master-ids/yubikey-1.pub ] ./shields/beta.nix.age
*/
extraBuiltins: identities: file:
let
  coerceMasterIdentity = import ./coerce-master-identity.nix;

  # The builtin takes paths and absolute path strings, so a key outside
  # the flake is named in place, never copied into the store.
  identityOf = entry: (coerceMasterIdentity entry).identity;

  # A loaded plugin with no extra-builtins file evaluates to null.
  hasBuiltin = builtins.isAttrs extraBuiltins && extraBuiltins ? importShield;

  noBuiltin = "nixos-shields: importShield builtin not loaded; use the wrapped Nix from lib.mkNix";
in
if !hasBuiltin then throw noBuiltin else extraBuiltins.importShield (map identityOf identities) file
