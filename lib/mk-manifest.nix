/*
  mkManifest — builds the manifest the command-line tool reads. Only
  file declarations are read, so building it never decrypts a shield.

  Inputs:
    self: the consumer's flake, or anything whose outPath or string
      form is the absolute flake root.
    configurations: evaluated configurations by name; each contributes
      its config.age.shields.files, masterIdentities, and
      extraEncryptionPubkeys, or none without the shields module.
      Defaults to { }.

  Returns { masterIdentities, extraEncryptionPubkeys,
  configurations.<name>.files } with every location inside the flake
  root a string relative to it, for use in a writable checkout. A shield
  file outside the root fails evaluation; a master identity outside it
  keeps its absolute location, so a plain key never has to live in the
  checkout. masterIdentities combines every configuration's list in
  configuration name order, each identity once as { identity, pubkey },
  so the tool encrypts every shield to all of them. pubkey is the public
  key any entry pairs the identity with, or else null; two different
  keys for one identity fail evaluation. No identity file is read: the
  tool reads a YubiKey or FIDO2 stub's public key itself when it
  encrypts. extraEncryptionPubkeys combines every configuration's list
  the same way, each entry once, as { pubkey } for
  a public key or { recipientsFile } for a recipients file, whose
  location follows the master identity rule.
*/
{
  self,
  configurations ? { },
}:
let
  inherit (builtins)
    attrValues
    concatMap
    elem
    foldl'
    isPath
    mapAttrs
    stringLength
    substring
    unsafeDiscardStringContext
    ;

  combineMasterIdentities = import ./combine-master-identities.nix;

  isAbsolute = location: substring 0 1 location == "/";

  # Manifest locations refer to the checkout. Drop store context before
  # normalizing paths lexically, without reading or copying any files.
  # A relative location throws.
  toAbsoluteLocation =
    path:
    let
      location = toString path;
    in
    if isAbsolute location then
      toString (/. + unsafeDiscardStringContext location)
    else
      throw "nixos-shields: manifest path ${location} must be absolute";

  root = toAbsoluteLocation self;
  prefix = root + "/";
  isInsideRoot = location: substring 0 (stringLength prefix) location == prefix;
  removeRootPrefix = location: substring (stringLength prefix) (-1) location;

  # A shield file must lie inside the root; one outside throws.
  toRelativeLocationOrThrow =
    path:
    let
      location = toAbsoluteLocation path;
    in
    if isInsideRoot location then
      removeRootPrefix location
    else
      throw "nixos-shields: manifest path ${location} is outside flake root ${root}";

  # A key file inside the root is relative to it; one outside, such as a
  # key under the home directory, stays absolute.
  toRelativeLocationOrAbsolute =
    path:
    let
      location = toAbsoluteLocation path;
    in
    if isInsideRoot location then removeRootPrefix location else location;

  # A relative identity string throws.
  toIdentityLocation =
    identity:
    let
      given = toString identity;
    in
    if !isAbsolute given then
      throw "nixos-shields: master identity ${given} must be a path or an absolute path string"
    else
      toRelativeLocationOrAbsolute given;

  # A path or an absolute string names a recipients file; any other
  # string is a public key.
  toExtraEncryptionPubkeyEntry =
    entry:
    if isPath entry || isAbsolute entry then
      { recipientsFile = toRelativeLocationOrAbsolute entry; }
    else
      { pubkey = entry; };

  addUnique = kept: entry: if elem entry kept then kept else kept ++ [ entry ];

  # Every configuration's entries of one option, in configuration name
  # order; a configuration without the shields module contributes none.
  configurationEntries =
    option:
    concatMap (configuration: configuration.config.age.shields.${option} or [ ]) (
      attrValues configurations
    );
in
{
  masterIdentities = combineMasterIdentities { inherit toIdentityLocation; } (
    configurationEntries "masterIdentities"
  );
  extraEncryptionPubkeys = foldl' addUnique [ ] (
    map toExtraEncryptionPubkeyEntry (configurationEntries "extraEncryptionPubkeys")
  );
  configurations = mapAttrs (_: configuration: {
    files = mapAttrs (_: toRelativeLocationOrThrow) (configuration.config.age.shields.files or { });
  }) configurations;
}
