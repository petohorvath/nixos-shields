/*
  importShield — decrypts a shield file and returns the Nix value it
  holds. The modules read shields only through this function, which
  hands the identity files to the builtin. This function names a Nix
  without the builtin, then checks the master identity entry forms,
  which only it and the NixOS module know; the builtin checks the
  locations, of the identity files and the shield file. Reading needs
  the wrapped Nix from mkNix.

  Inputs:
    extraBuiltins: the running Nix's builtins.extraBuiltins, or null
      without one. lib and the NixOS module apply it, so the public
      importShield takes the two arguments below.
    identities: the master identities, any one of which can decrypt the
      shield, in the forms age.shields.masterIdentities accepts: a path,
      an absolute path string, or { identity; pubkey; } with pubkey
      optional, null or a public key. Only the identity files are used;
      a public key matters only to encryption.
    file: the shield file, a path or an absolute path string whose name
      ends in `.nix.age`.

  Returns the value of the decrypted Nix expression.

  Example:
    importShield [ ./master-ids/yubikey-1.pub ] ./shields/beta.nix.age
*/
extraBuiltins: identities: file:
let
  inherit (builtins)
    all
    attrNames
    elemAt
    filter
    genList
    head
    isAttrs
    isList
    isPath
    isString
    length
    ;

  coerceMasterIdentity = import ./coerce-master-identity.nix;
  inherit (import ./public-key.nix) isPublicKey notPublicKeyMessage;

  # The builtin takes paths and absolute path strings, so a key outside
  # the flake is named in place, never copied into the store.
  identityOf = entry: (coerceMasterIdentity entry).identity;

  # A loaded plugin with no extra-builtins file evaluates to null.
  hasBuiltin = isAttrs extraBuiltins && extraBuiltins ? importShield;

  noBuiltin = "nixos-shields: importShield builtin not loaded; use the wrapped Nix from lib.mkNix";
  notList = "nixos-shields: the master identities must be a list of paths, absolute path strings, or { identity; pubkey; }";

  # True for a valid entry form; throws for any other, naming the
  # entry's position, counted from 1. Whether a path or string is an
  # absolute location is the builtin's check.
  assertEntry =
    position: entry:
    let
      entryName = "master identity entry ${toString position}";
      label = "nixos-shields: ${entryName}";
      unknownAttributes = filter (name: name != "identity" && name != "pubkey") (attrNames entry);
    in
    if isPath entry || isString entry then
      true
    else if !isAttrs entry then
      throw "${label} must be a path, an absolute path string, or { identity; pubkey; }"
    else if !(entry ? identity) then
      throw "${label} has no identity"
    else if unknownAttributes != [ ] then
      throw "${label} has the unknown attribute ${head unknownAttributes}; it takes only identity and pubkey"
    else if (entry.pubkey or null) != null && !isPublicKey entry.pubkey then
      throw "nixos-shields: the pubkey of ${entryName} ${notPublicKeyMessage}"
    else
      true;

  # Forces every entry's check before any identity reaches the builtin.
  entriesValid = all (valid: valid) (
    genList (index: assertEntry (index + 1) (elemAt identities index)) (length identities)
  );
in
if !hasBuiltin then
  throw noBuiltin
else if !isList identities then
  throw notList
else
  assert entriesValid;
  extraBuiltins.importShield (map identityOf identities) file
