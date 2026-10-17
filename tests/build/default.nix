{ inputs, pkgs }:
let
  testArgs = { inherit inputs pkgs; };
in
{
  cli = import ./cli.nix testArgs;
  decrypt-cache = import ./decrypt-cache.nix testArgs;
  wrapped-nix = import ./wrapped-nix.nix testArgs;
}
