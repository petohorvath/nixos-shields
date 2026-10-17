{ inputs, pkgs }:
let
  inherit (pkgs) lib;
  testArgs = { inherit inputs pkgs; };
  prefixNames = prefix: lib.mapAttrs' (name: lib.nameValuePair "${prefix}-${name}");
in
prefixNames "build" (import ./build testArgs)
