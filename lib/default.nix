{
  importShield = import ./import-shield.nix (builtins.extraBuiltins or null);
  mkManifest = import ./mk-manifest.nix;
  mkNix = import ./mk-nix.nix;
}
