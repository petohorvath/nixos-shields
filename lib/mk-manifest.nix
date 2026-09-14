/*
  mkManifest — the inventory consumed by the command-line tool. Only
  file declarations are read, so building it never decrypts a shield.
  Locations are relative to self, for use in a writable flake checkout.
*/
{
  self,
  masterIdentities ? [ ],
  files ? { },
  configurations ? { },
}:
let
  inherit (builtins) mapAttrs stringLength substring;

  # Manifest locations refer to the checkout. Drop store context before
  # normalizing paths lexically, without reading or copying any files.
  normalize =
    path:
    let
      location = toString path;
    in
    if substring 0 1 location == "/" then
      toString (/. + builtins.unsafeDiscardStringContext location)
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
