{
  perSystem =
    { pkgs, ... }:
    let
      nix = (import ../lib).mkNix { inherit pkgs; };
    in
    {
      # The plugin and builtins file are the ones the wrapped Nix loads.
      packages = {
        inherit nix;
        nix-plugins = nix.plugins;
        extra-builtins = nix.extraBuiltinsFile;
        decrypt = pkgs.callPackage ../packages/decrypt { };
      };
    };
}
