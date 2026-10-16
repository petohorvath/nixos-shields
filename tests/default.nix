{ inputs, pkgs }:
let
  inherit (pkgs) lib;
  repo = "nixos-shields";

  # The files the nix-unit suites read, not the docs or the build tests,
  # so neither a README edit nor a build test change reruns the suites.
  srcDir = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../examples/consumer/shields
      ../flake.nix
      ../flake-module.nix
      ../lib
      ../nixos
      ../packages
      ./fixtures
      ./helpers
      ./integration
      ./test-context.nix
      ./unit
    ];
  };

  runNixUnit = import ./runners/nix-unit.nix {
    inherit
      inputs
      pkgs
      repo
      srcDir
      ;
  };
  runBuild = import ./runners/build.nix { inherit pkgs repo; };
in
lib.foldl' lib.attrsets.unionOfDisjoint { } [
  {
    unit = runNixUnit { kind = "unit"; };
    integration = runNixUnit { kind = "integration"; };
  }
  (runBuild (import ./build { inherit inputs pkgs; }))
]
