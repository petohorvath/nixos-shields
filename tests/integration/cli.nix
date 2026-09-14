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
      kit
      nixpkgs
      flakeParts
      ;
    inherit (nix) extraBuiltinsFile;
  }
  ''
    export HOME=$TMPDIR/home
    export XDG_CACHE_HOME=$HOME/.cache
    export XDG_CONFIG_HOME=$HOME/.config
    export XDG_DATA_HOME=$HOME/.local/share
    export XDG_STATE_HOME=$HOME/.local/state
    export NIXOS_SHIELDS_CACHE_DIR=$TMPDIR/decrypt-cache
    export NIX_REMOTE="local?real=/nix/store&state=$TMPDIR/state&log=$TMPDIR/log"
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
