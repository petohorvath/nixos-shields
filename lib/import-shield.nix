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

  # The builtin takes paths, and agenix-rekey gives absolute strings. A
  # path made from one names the same file without copying it.
  toIdentityPath =
    entry:
    let
      inherit (coerceMasterIdentity entry) identity;
    in
    if builtins.isPath identity then
      identity
    else if builtins.substring 0 1 identity == "/" then
      /. + builtins.unsafeDiscardStringContext identity
    else
      throw "nixos-shields: master identity ${identity} must be a path or an absolute path string";

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
  extraBuiltins.importShield (map toIdentityPath identities) file
