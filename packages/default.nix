# The plugin and builtins file are the ones the wrapped Nix loads.
pkgs:
let
  nix = import ../lib/mk-nix.nix { inherit pkgs; };
  nixos-shields = pkgs.callPackage ./cli/package.nix { inherit nix; };
in
{
  inherit nix nixos-shields;
  nix-plugins = nix.plugins;
  extra-builtins = nix.extraBuiltinsFile;
  decrypt = pkgs.callPackage ./decrypt/package.nix { };
  default = nixos-shields;
}
