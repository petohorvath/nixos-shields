# Seam 2: the packaged command over a writable example consumer, with
# real encryption and wrapped Nix evaluation in the build sandbox.
{ inputs, pkgs }:
let
  inherit (pkgs) lib;
  inherit (inputs.self.packages.${pkgs.stdenv.hostPlatform.system}) nix nixos-shields;

  example = ../../examples/consumer;
  flakeParts = inputs.flake-parts;
  nixUnit = inputs.nix-unit;
  inherit (inputs) nixpkgs;

  # The kit as the example's input: its flake and code, not its docs,
  # dev/, or tests/, which the example never reads, so neither a README
  # edit nor a tooling change rebuilds this test.
  kit = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../flake.nix
      ../../flake-module.nix
      ../../lib
      ../../nixos
      ../../packages
    ];
  };

  nativeBuildInputs = [
    nix
    nixos-shields
    pkgs.jq
    pkgs.openssh
    pkgs.rage
  ];

  /*
    Registration for the sandbox's inputs. Evaluating the example can add
    one of them, such as a stdenv setup hook, to the store again; if it is
    unregistered, its read-only copy blocks the write. The builder scripts
    are inputs of this derivation rather than of stdenv's closure.
  */
  builderScripts = builtins.filter builtins.isPath (pkgs.runCommand "builder-scripts" { } "").args;
  sandboxRegistration = pkgs.closureInfo {
    rootPaths = map (path: "${path}") (
      [
        pkgs.stdenvNoCC
        example
        flakeParts
        kit
        nixpkgs
        nixUnit
        nix.extraBuiltinsFile
      ]
      ++ nativeBuildInputs
      ++ builderScripts
    );
  };
in
pkgs.runCommand "nixos-shields-cli"
  {
    inherit
      example
      flakeParts
      kit
      nativeBuildInputs
      nixpkgs
      nixUnit
      ;
  }
  ''
    export HOME=$TMPDIR/home
    export NIXOS_SHIELDS_CACHE_DIR=$TMPDIR/decrypt-cache
    NIX_REMOTE="local?real=$NIX_STORE&state=$TMPDIR/state"
    export NIX_REMOTE="$NIX_REMOTE&log=$TMPDIR/log"
    mkdir -p "$HOME"

    # Make the sandbox inputs known to the evaluation store without taking
    # ownership of them.
    nix-store --store "$NIX_REMOTE" --load-db \
      < ${sandboxRegistration}/registration

    # A space in the checkout name exercises path handling too.
    consumer="$TMPDIR/example consumer"
    cp -R "$example" "$consumer"
    chmod -R u+w "$consumer"
    cd "$consumer"
    nix flake lock --extra-experimental-features 'nix-command flakes' \
      --override-input nixpkgs "path:$nixpkgs" \
      --override-input nixos-shields "path:$kit" \
      --override-input flake-parts "path:$flakeParts" \
      --override-input nixos-shields/nix-unit "path:$nixUnit"

    ${builtins.readFile ./cli.sh}
    touch "$out"
  ''
