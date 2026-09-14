/*
  The wrapped Nix, driven from where a consumer stands, inside the
  build sandbox (seam 1 of the spec's testing decisions). A chroot
  store under the build directory accepts new paths, so a stray copy
  of the shield file would be observable.
*/
{
  runCommand,
  jq,
  nix,
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
    export XDG_CACHE_HOME=$HOME/.cache
    export XDG_CONFIG_HOME=$HOME/.config
    export XDG_DATA_HOME=$HOME/.local/share
    export XDG_STATE_HOME=$HOME/.local/state
    export NIXOS_SHIELDS_CACHE_DIR=$TMPDIR/cache
    store=$TMPDIR/store
    mkdir -p "$HOME" "$NIXOS_SHIELDS_CACHE_DIR" "$store"
    cd "$TMPDIR"

    fail() { echo "FAIL: $*" >&2; exit 1; }

    evalJson() {
      nix eval --store "$store" --impure --json \
        --extra-experimental-features 'nix-command flakes' \
        --expr "$1"
    }

    # The wrapper sets NIX_CONFIG for the nix process only.
    [[ -z "''${NIX_CONFIG:-}" ]] || fail "NIX_CONFIG leaked into the shell"
    nix-store --version | grep -q '^nix-store (Nix) 2\.34\.' \
      || fail "nix-store lost its multi-call identity"
    nix-build --version | grep -q '^nix-build (Nix) 2\.34\.' \
      || fail "nix-build lost its multi-call identity"
    nix-instantiate --store "$store" --eval --expr 'builtins ? extraBuiltins' \
      | grep -qx true || fail "nix-instantiate does not load the builtin"
    evalJson 'builtins ? extraBuiltins' | grep -qx true \
      || fail "nix does not load the builtin"

    # A throwaway key and a fixture encrypted to it, made at check time.
    rage-keygen -o key.txt 2>/dev/null
    echo '{ domain = "example.test"; answer = 42; }' > fixture.nix
    rage --encrypt --identity key.txt --output fixture.nix.age fixture.nix
    rm fixture.nix

    lib="(import $libDir)"

    expected='{"answer":42,"domain":"example.test"}'
    shield="$lib.importShield [ $TMPDIR/key.txt ]"
    actual=$(evalJson "$shield $TMPDIR/fixture.nix.age" | jq -cS .)
    [[ $actual == "$expected" ]] \
      || fail "decrypted value was $actual, expected $expected"

    expectFailure() {
      local expression=$1 pattern=$2 what=$3
      if evalJson "$expression" 2> stderr.log; then
        fail "$what: evaluation succeeded"
      fi
      grep -q -- "$pattern" stderr.log \
        || fail "$what: message lacks '$pattern'"
    }

    expectFailure "$shield $TMPDIR/missing.nix.age" \
      "$TMPDIR/missing.nix.age" "missing shield file"
    expectFailure "$lib.importShield [ ] $TMPDIR/fixture.nix.age" \
      "no master identity" "empty master identities"

    # The suffix check inspects the base name, so the eval store holds no
    # copy of any shield file after all of the above.
    copies=$(find "$store" -name '*.nix.age')
    [[ -z $copies ]] || fail "shield file copied into the eval store: $copies"

    touch "$out"
  ''
