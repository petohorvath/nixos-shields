/*
  mkManifest — builds the manifest the command-line tool reads. Only
  file declarations are read, so building it never decrypts a shield.

  Inputs:
    self: the consumer's flake, or anything whose outPath or string
      form is the absolute flake root.
    configurations: evaluated configurations by name; each contributes
      its config.age.shields.files and masterIdentities, or none without
      the shields module. Defaults to { }.

  Returns { masterIdentities, configurations.<name>.files } with every
  location inside the flake root a string relative to it, for use in a
  writable checkout. A shield file outside the root fails evaluation; a
  master identity outside it keeps its absolute location, so a plain
  key never has to live in the checkout. masterIdentities combines every
  configuration's list in configuration name order, each identity once
  as { identity, pubkey }, so the tool encrypts every shield to all of
  them. pubkey is the public key any entry pairs the identity with; two
  different keys for one identity fail evaluation. Without one, it is
  the key read from a YubiKey or FIDO2 stub given as a path inside the
  flake root, or else null.
*/
{
  self,
  configurations ? { },
}:
let
  inherit (builtins)
    any
    attrValues
    concatMap
    filter
    foldl'
    head
    isPath
    mapAttrs
    stringLength
    substring
    unsafeDiscardStringContext
    ;

  coerceMasterIdentity = import ./coerce-master-identity.nix;
  readStubPubkey = import ./read-stub-pubkey.nix;

  # Manifest locations refer to the checkout. Drop store context before
  # normalizing paths lexically, without reading or copying any files.
  normalize =
    path:
    let
      location = toString path;
    in
    if substring 0 1 location == "/" then
      toString (/. + unsafeDiscardStringContext location)
    else
      throw "nixos-shields: manifest path ${location} must be absolute";

  root = normalize self;
  prefix = root + "/";
  isInsideRoot = location: substring 0 (stringLength prefix) location == prefix;
  fromRoot = location: substring (stringLength prefix) (-1) location;
  relative =
    path:
    let
      location = normalize path;
    in
    if isInsideRoot location then
      fromRoot location
    else
      throw "nixos-shields: manifest path ${location} is outside flake root ${root}";

  # An identity inside the root is relative to it; one outside, such as a
  # key under the home directory, stays absolute.
  identityLocation =
    identity:
    let
      given = toString identity;
      location = normalize given;
    in
    if substring 0 1 given != "/" then
      throw "nixos-shields: master identity ${given} must be a path or an absolute path string"
    else if isInsideRoot location then
      fromRoot location
    else
      location;

  # Only a path inside the root may be read: it belongs to the flake's
  # source, so reading it keeps building the manifest pure. A string, or
  # anything outside the root, is never read.
  readablePath =
    identity: if isPath identity && isInsideRoot (normalize identity) then identity else null;

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
      identity = identityLocation entry.identity;
      inherit (entry) pubkey;
      stubPath = readablePath entry.identity;
      isSame = previous: previous.identity == identity;
      previous = head (filter isSame kept);
      merge =
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
      map merge kept;

  # A declared public key wins, so the stub is read only without one.
  withStubPubkey =
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

  configurationIdentities = concatMap (
    configuration: map coerceMasterIdentity (configuration.config.age.shields.masterIdentities or [ ])
  ) (attrValues configurations);
in
{
  masterIdentities = map withStubPubkey (foldl' addIdentity [ ] configurationIdentities);
  configurations = mapAttrs (_: configuration: {
    files = mapAttrs (_: relative) (configuration.config.age.shields.files or { });
  }) configurations;
}
