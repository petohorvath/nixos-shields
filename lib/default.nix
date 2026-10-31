{
  importShield = import ./import-shield.nix (builtins.extraBuiltins or null);
  mkManifest = import ./mk-manifest.nix;
  mkExtraBuiltinsFile = import ./mk-extra-builtins-file.nix;
  mkNix = import ./mk-nix.nix;
}
