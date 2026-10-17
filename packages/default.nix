# The plugin and builtins file are the ones the wrapped Nix loads.
pkgs:
let
  nix = import ../lib/mk-nix.nix { inherit pkgs; };
  decrypt = pkgs.callPackage ./decrypt/package.nix { };
  nixos-shields = pkgs.callPackage ./cli/package.nix { inherit decrypt nix; };
in
{
  inherit decrypt nix nixos-shields;
  nix-plugins = nix.plugins;
  extra-builtins = nix.extraBuiltinsFile;
  default = nixos-shields;
}
