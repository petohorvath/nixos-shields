/*
  The wrapped Nix, driven from where a consumer stands, inside the
  build sandbox (seam 1 of the spec's testing decisions): the multi-call
  binaries, then the library function on a fixture made at check time,
  directly and through a consumer's combined extra-builtins file. The cli
  check evaluates the example consumer.

  The sandbox's store directory is group-writable, so the check opens a
  Nix store whose physical directory is that one and whose database lives
  under the build directory.
*/
{
  runCommand,
  jq,
  nix,
  composedNix,
  rage,
  libDir,
}:
runCommand "nixos-shields-integration"
  {
    nativeBuildInputs = [
      jq
      nix
      rage
    ];
    inherit libDir;
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

    # The fixture lives outside the store; reading it must not copy it in.
    copies=$(find "$NIX_STORE" -maxdepth 1 -name '*.nix.age')
    [[ -z $copies ]] || fail "shield file copied into the store: $copies"

    touch "$out"
  ''
