/*
  Seam 2: the packaged command over a writable example consumer, with
  real encryption and wrapped Nix evaluation in the build sandbox.
*/
{
  runCommand,
  jq,
  nix,
  nixos-shields,
  rage,
  example,
  kit,
  nixpkgs,
  flakeParts,
}:
runCommand "nixos-shields-cli"
  {
    nativeBuildInputs = [
      jq
      nix
      nixos-shields
      rage
    ];
    inherit
      example
      flakeParts
      kit
      nixpkgs
      ;
    inherit (nix) extraBuiltinsFile;
  }
  ''
    export HOME=$TMPDIR/home
    export NIXOS_SHIELDS_CACHE_DIR=$TMPDIR/decrypt-cache
    NIX_REMOTE="local?real=$NIX_STORE&state=$TMPDIR/state"
    export NIX_REMOTE="$NIX_REMOTE&log=$TMPDIR/log"
    mkdir -p "$HOME"

    ${builtins.readFile ./register-store-path.sh}
    registerStorePath "$NIX_REMOTE" "$extraBuiltinsFile"
    registerStorePath "$NIX_REMOTE" "$nixpkgs"
    registerStorePath "$NIX_REMOTE" "$flakeParts"
    registerStorePath "$NIX_REMOTE" "$kit"

    # A space in the checkout name exercises path handling too.
    consumer="$TMPDIR/example consumer"
    cp -R "$example" "$consumer"
    chmod -R u+w "$consumer"
    cd "$consumer"
    nix flake lock --extra-experimental-features 'nix-command flakes' \
      --override-input nixpkgs "path:$nixpkgs" \
      --override-input nixos-shields "path:$kit" \
      --override-input flake-parts "path:$flakeParts"

    ${builtins.readFile ./cli.sh}
    touch "$out"
  ''
