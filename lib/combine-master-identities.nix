/*
  Combines master identity entries, in any form the NixOS module
  accepts, into a list of { identity, pubkey } holding each identity
  once, at its first position.

  Inputs:
    toIdentityLocation: converts an entry's identity to the location
      that identifies it in the manifest; it may throw for an invalid
      identity.
    toReadablePathOrNull: returns the identity as a path that may be
      read for a stub's public key, or null when it must not be read.
    entries: the master identity entries, in order.

  pubkey is the public key any entry pairs the identity with; two
  different keys for one identity fail evaluation, naming it. Without
  one, it is the key read from the first readable stub path given for
  the identity, or else null.
*/
{ toIdentityLocation, toReadablePathOrNull }:
entries:
let
  inherit (builtins)
    any
    filter
    foldl'
    head
    ;

  coerceMasterIdentity = import ./coerce-master-identity.nix;
  readStubPubkey = import ./read-stub-pubkey.nix;

  /*
    Adds an entry to the identities kept so far. A repeated identity keeps
    its first position and takes the public key of whichever entry has
    one. Each kept identity also remembers the first readable path given
    for it, from which a stub's public key is read when no entry declares
    one.
  */
  addIdentity =
    kept: entry:
    let
      identity = toIdentityLocation entry.identity;
      inherit (entry) pubkey;
      stubPath = toReadablePathOrNull entry.identity;
      isSame = previous: previous.identity == identity;
      previous = head (filter isSame kept);
      mergeIntoSame =
        candidate:
        if isSame candidate then
          candidate
          // {
            pubkey = if pubkey != null then pubkey else candidate.pubkey;
            stubPath = if candidate.stubPath != null then candidate.stubPath else stubPath;
          }
        else
          candidate;
    in
    if !any isSame kept then
      kept ++ [ { inherit identity pubkey stubPath; } ]
    else if previous.pubkey != null && pubkey != null && previous.pubkey != pubkey then
      throw "nixos-shields: master identity ${identity} is paired with different public keys: ${previous.pubkey} and ${pubkey}"
    else
      map mergeIntoSame kept;

  # A declared public key wins, so the stub is read only without one.
  resolvePubkey =
    {
      identity,
      pubkey,
      stubPath,
    }:
    {
      inherit identity;
      pubkey =
        if pubkey != null then
          pubkey
        else if stubPath != null then
          readStubPubkey stubPath
        else
          null;
    };
in
map resolvePubkey (foldl' addIdentity [ ] (map coerceMasterIdentity entries))
