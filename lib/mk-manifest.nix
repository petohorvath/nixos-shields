/*
  mkManifest — builds the manifest the command-line tool reads. Only
  file declarations are read, so building it never decrypts a shield.

  Inputs:
    self: the consumer's flake, or anything whose outPath or string
      form is the absolute flake root.
    masterIdentities: the master identity files, a list of paths or
      absolute strings; defaults to [ ].
    files: the flake-scoped shield files by name; defaults to { }.
    configurations: evaluated configurations by name; each contributes
      its config.age.shields.files, or none without the shields module.
      Defaults to { }.

  Returns { masterIdentities, files, configurations.<name>.files } with
  every location a string relative to the flake root, for use in a
  writable checkout. A location outside the root fails evaluation.
*/
{
  self,
  masterIdentities ? [ ],
  files ? { },
  configurations ? { },
}:
let
  inherit (builtins)
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

  relativeFiles = mapAttrs (_: relative);
in
{
  masterIdentities = map relative masterIdentities;
  files = relativeFiles files;
  configurations = mapAttrs (_: configuration: {
    files = relativeFiles (configuration.config.age.shields.files or { });
  }) configurations;
}
