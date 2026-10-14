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
  location a string relative to the flake root, for use in a writable
  checkout. A location outside the root fails evaluation.
  masterIdentities combines every configuration's list in configuration
  name order, each identity once, so the tool encrypts every shield to
  all of them.
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
    mapAttrs
    stringLength
    substring
    unsafeDiscardStringContext
    ;

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
  relative =
    path:
    let
      location = normalize path;
    in
    if substring 0 (stringLength prefix) location == prefix then
      substring (stringLength prefix) (-1) location
    else
      throw "nixos-shields: manifest path ${location} is outside flake root ${root}";

  # Keeps the first occurrence of each location.
  unique = foldl' (kept: location: if elem location kept then kept else kept ++ [ location ]) [ ];

  configurationIdentities = concatMap (
    configuration: configuration.config.age.shields.masterIdentities or [ ]
  ) (attrValues configurations);
in
{
  masterIdentities = unique (map relative configurationIdentities);
  configurations = mapAttrs (_: configuration: {
    files = mapAttrs (_: relative) (configuration.config.age.shields.files or { });
  }) configurations;
}
