/*
  The wrapped Nix, driven from where a consumer stands, inside the
  build sandbox (seam 1 of the spec's testing decisions): the multi-call
  binaries, then the library function on a fixture made at check time,
  directly and through a consumer's combined extra-builtins file. The cli
  test evaluates the example consumer.

  The sandbox's store directory is group-writable, so the check opens a
  Nix store whose physical directory is that one and whose database lives
  under the build directory.
*/
{ inputs, pkgs }:
let
  inherit (inputs.self.packages.${pkgs.stdenv.hostPlatform.system}) nix;

  # A consumer's extra-builtins file that adds its own builtin.
  composedNix = inputs.self.lib.mkNix {
    inherit pkgs;
    extraBuiltinsFile = pkgs.writeText "consumer-extra-builtins.nix" ''
      args:
      (import ${nix.extraBuiltinsFile} args) // {
        consumerAnswer = 42;
      }
    '';
  };
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

    # The attribute set entry form decrypts with its identity alone, the
    # identity given as a path or, as agenix-rekey gives it, a string.
    pubkey=$(rage-keygen -y identity.txt)
    for identity in "$TMPDIR/identity.txt" "\"$TMPDIR/identity.txt\""; do
      entries="[ { identity = $identity; pubkey = \"$pubkey\"; } ]"
      entryShield="$lib.importShield $entries $TMPDIR/fixture.nix.age"
      actual=$(evalJson nix "$entryShield" | jq -cS .)
      [[ $actual == "$expected" ]] \
        || fail "decrypting with $entries returned $actual, expected $expected"
    done

    # The builtin itself takes an identity as an absolute path string,
    # and rejects a relative one.
    builtin="builtins.extraBuiltins.importShield"
    stringShield="$builtin [ \"$TMPDIR/identity.txt\" ] $TMPDIR/fixture.nix.age"
    actual=$(evalJson nix "$stringShield" | jq -cS .)
    [[ $actual == "$expected" ]] \
      || fail "the builtin returned $actual for a string identity," \
        "expected $expected"
    relativeShield="$builtin [ \"identity.txt\" ] $TMPDIR/fixture.nix.age"
    if evalJson nix "$relativeShield" 2> relative.log; then
      fail "the builtin accepted a relative identity string"
    fi
    grep -q 'absolute path strings' relative.log \
      || fail "relative identity failure was: $(cat relative.log)"

    # A consumer's own extra-builtins file keeps both its additions
    # and importShield when handed to lib.mkNix.
    composed="{
      shield = $shield $TMPDIR/fixture.nix.age;
      consumerAnswer = builtins.extraBuiltins.consumerAnswer;
    }"
    actual=$(evalJson ${composedNix}/bin/nix "$composed" | jq -cS .)
    expected='{"consumerAnswer":42,'
    expected+='"shield":{"answer":42,"domain":"example.test"}}'
    [[ $actual == "$expected" ]] \
      || fail "composed builtins returned $actual, expected $expected"

    # The fixture and the identity live outside the store; reading them
    # must not copy them in.
    copies=$(find "$NIX_STORE" -maxdepth 1 \
      -name '*.nix.age' -o -name '*-identity.txt')
    [[ -z $copies ]] \
      || fail "shield file or identity copied into the store: $copies"

    touch "$out"
  ''
