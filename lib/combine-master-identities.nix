/*
  Combines master identity entries, in any form the NixOS module
  accepts, into a list of { identity, pubkey } holding each identity
  once, at its first position.

  Inputs:
    toIdentityLocation: converts an entry's identity to the location
      that identifies it in the manifest; it may throw for an invalid
      identity.
    entries: the master identity entries, in order.

  pubkey is the public key any entry pairs the identity with, or else
  null; two different keys for one identity fail evaluation, naming it.
  No identity file is read.
*/
{ toIdentityLocation }:
entries:
let
  inherit (builtins)
    any
    filter
    foldl'
    head
    ;

  coerceMasterIdentity = import ./coerce-master-identity.nix;

  /*
    Adds an entry to the identities kept so far. A repeated identity keeps
    its first position and takes the public key of whichever entry has
    one.
  */
  addIdentity =
    kept: entry:
    let
      identity = toIdentityLocation entry.identity;
      inherit (entry) pubkey;
      isSame = previous: previous.identity == identity;
      previous = head (filter isSame kept);
      mergeIntoSame =
        candidate:
        if isSame candidate && pubkey != null then candidate // { inherit pubkey; } else candidate;
    in
    if !any isSame kept then
      kept ++ [ { inherit identity pubkey; } ]
    else if previous.pubkey != null && pubkey != null && previous.pubkey != pubkey then
      throw "nixos-shields: master identity ${identity} is paired with different public keys: ${previous.pubkey} and ${pubkey}"
    else
      map mergeIntoSame kept;
in
foldl' addIdentity [ ] (map coerceMasterIdentity entries)
