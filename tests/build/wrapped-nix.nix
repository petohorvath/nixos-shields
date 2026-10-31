/*
  The wrapped Nix, driven from where a consumer stands, inside the
  build sandbox (seam 1 of the spec's testing decisions): the multi-call
  binaries, then the library function on a fixture made at check time,
  with the kit's builtins alone and beside a consumer's extra builtins,
  the builtin with string arguments, and the consumer's builtins in pure
  evaluation. The builtin's checks and the
  identities lib.importShield hands it are in the unit suites. The cli
  test evaluates the example consumer.

  The sandbox's store directory is group-writable, so the check opens a
  Nix store whose physical directory is that one and whose database lives
  under the build directory.
*/
{ inputs, pkgs }:
let
  inherit (inputs.self.packages.${pkgs.stdenv.hostPlatform.system}) nix;

  /*
    A consumer's builtins: a file, and a directory whose default.nix
    imports a file beside it, which only the bundle's copy can reach in
    pure evaluation.
  */
  composedNix = inputs.self.lib.mkNix {
    inherit pkgs;
    extraBuiltins = [
      (pkgs.writeText "answer.nix" "_: { consumerAnswer = 42; }")
      (pkgs.runCommand "greeting" { } ''
        mkdir "$out"
        echo '_: { consumerGreeting = import ./greeting.nix; }' > "$out/default.nix"
        echo '"hello"' > "$out/greeting.nix"
      '')
    ];
  };

  # Pure evaluation reads only valid store paths, so the check's store
  # learns the composed bundle, as building it would register it.
  bundleRegistration = pkgs.closureInfo { rootPaths = [ composedNix.extraBuiltinsDir ]; };
in
pkgs.runCommand "nixos-shields-wrapped-nix"
  {
    nativeBuildInputs = [
      nix
      pkgs.jq
      pkgs.rage
    ];
    libDir = ../../lib;
  }
  ''
    export HOME=$TMPDIR/home
    export NIXOS_SHIELDS_CACHE_DIR=$TMPDIR/cache
    store="local?real=$NIX_STORE&state=$TMPDIR/state&log=$TMPDIR/log"
    mkdir -p "$HOME" "$NIXOS_SHIELDS_CACHE_DIR"
    cd "$TMPDIR"

    fail() { echo "FAIL: $*" >&2; exit 1; }

    # evalJson <nix> <expression>
    evalJson() {
      "$1" eval --store "$store" --json --impure \
        --extra-experimental-features 'nix-command flakes' --expr "$2"
    }

    # evalPureJson <nix> <expression>, in the pure evaluation mode of
    # flake commands such as nixos-rebuild --flake.
    evalPureJson() {
      "$1" eval --store "$store" --json \
        --extra-experimental-features 'nix-command flakes' --expr "$2"
    }

    # The wrapper sets NIX_CONFIG for the nix process only.
    [[ -z "''${NIX_CONFIG:-}" ]] || fail "NIX_CONFIG leaked into the shell"
    nix-store --version | grep -q '^nix-store (Nix) 2\.34\.' \
      || fail "nix-store lost its multi-call identity"
    nix-build --version | grep -q '^nix-build (Nix) 2\.34\.' \
      || fail "nix-build lost its multi-call identity"
    nix-instantiate --store "$store" --eval --expr 'builtins ? extraBuiltins' \
      | grep -qx true || fail "nix-instantiate does not load the builtin"
    evalJson nix 'builtins ? extraBuiltins' | grep -qx true \
      || fail "nix does not load the builtin"

    # A throwaway identity and a fixture encrypted to it, made at check time.
    rage-keygen -o identity.txt 2>/dev/null
    echo '{ domain = "example.test"; answer = 42; }' > fixture.nix
    rage --encrypt --identity identity.txt --output fixture.nix.age fixture.nix
    rm fixture.nix

    lib="(import $libDir)"

    expected='{"answer":42,"domain":"example.test"}'
    shield="$lib.importShield [ $TMPDIR/identity.txt ]"
    actual=$(evalJson nix "$shield $TMPDIR/fixture.nix.age" | jq -cS .)
    [[ $actual == "$expected" ]] \
      || fail "decrypted value was $actual, expected $expected"

    # Real exec takes a shield file given as an absolute path string, as
    # it takes an identity one. The fake exec of the unit suites cannot
    # show this.
    builtin="builtins.extraBuiltins.importShield"
    stringShield="$builtin [ \"$TMPDIR/identity.txt\" ]"
    stringShield+=" \"$TMPDIR/fixture.nix.age\""
    actual=$(evalJson nix "$stringShield" | jq -cS .)
    [[ $actual == "$expected" ]] \
      || fail "the builtin returned $actual for string arguments," \
        "expected $expected"

    # A consumer's builtins handed to lib.mkNix sit beside importShield,
    # which still decrypts.
    composed="{
      shield = $shield $TMPDIR/fixture.nix.age;
      consumerAnswer = builtins.extraBuiltins.consumerAnswer;
    }"
    actual=$(evalJson ${composedNix}/bin/nix "$composed" | jq -cS .)
    expected='{"consumerAnswer":42,'
    expected+='"shield":{"answer":42,"domain":"example.test"}}'
    [[ $actual == "$expected" ]] \
      || fail "composed builtins returned $actual, expected $expected"

    # Pure evaluation admits only the extra-builtins file's own tree, so
    # the composed builtins must load without --impure.
    nix-store --store "$store" --load-db < ${bundleRegistration}/registration
    pure="with builtins.extraBuiltins; {
      importShield = builtins.isFunction importShield;
      inherit consumerAnswer consumerGreeting;
    }"
    actual=$(evalPureJson ${composedNix}/bin/nix "$pure" | jq -cS .)
    expected='{"consumerAnswer":42,"consumerGreeting":"hello",'
    expected+='"importShield":true}'
    [[ $actual == "$expected" ]] \
      || fail "composed builtins in pure evaluation returned $actual," \
        "expected $expected"

    # The fixture and the identity live outside the store; reading them
    # must not copy them in.
    copies=$(find "$NIX_STORE" -maxdepth 1 \
      -name '*.nix.age' -o -name '*-identity.txt')
    [[ -z $copies ]] \
      || fail "shield file or identity copied into the store: $copies"

    touch "$out"
  ''
