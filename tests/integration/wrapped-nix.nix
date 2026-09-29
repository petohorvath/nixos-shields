/*
  The wrapped Nix, driven from where a consumer stands, inside the
  build sandbox (seam 1 of the spec's testing decisions): the library
  function on a fixture made at check time, then the example consumer
  evaluated as a flake.

  The sandbox's store directory is group-writable, so the check opens a
  Nix store whose physical directory is that one and whose database lives
  under the build directory. Paths the sandbox already holds (the kit
  and its inputs) are registered rather than copied, and the
  example's flake source lands where the decrypt script can read it:
  with a chroot store it would exist only under the store's root.
*/
{
  runCommand,
  jq,
  nix,
  composedNix,
  rage,
  libDir,
  example,
  kit,
  nixpkgs,
  flakeParts,
}:
runCommand "nixos-shields-integration"
  {
    nativeBuildInputs = [
      jq
      nix
      rage
    ];
    inherit
      example
      flakeParts
      kit
      libDir
      nixpkgs
      ;
    inherit (nix) extraBuiltinsFile;
  }
  ''
    export HOME=$TMPDIR/home
    export XDG_CACHE_HOME=$HOME/.cache
    export XDG_CONFIG_HOME=$HOME/.config
    export XDG_DATA_HOME=$HOME/.local/share
    export XDG_STATE_HOME=$HOME/.local/state
    export NIXOS_SHIELDS_CACHE_DIR=$TMPDIR/cache
    store="local?real=$NIX_STORE&state=$TMPDIR/state&log=$TMPDIR/log"
    mkdir -p "$HOME" "$NIXOS_SHIELDS_CACHE_DIR"
    cd "$TMPDIR"

    fail() { echo "FAIL: $*" >&2; exit 1; }

    ${builtins.readFile ./register-store-path.sh}

    nixEval() {
      nix eval --store "$store" --json \
        --extra-experimental-features 'nix-command flakes' "$@"
    }

    evalJson() { nixEval --impure --expr "$1"; }

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

    # A throwaway identity and a fixture encrypted to it, made at check time.
    rage-keygen -o identity.txt 2>/dev/null
    echo '{ domain = "example.test"; answer = 42; }' > fixture.nix
    rage --encrypt --identity identity.txt --output fixture.nix.age fixture.nix
    rm fixture.nix

    lib="(import $libDir)"

    expected='{"answer":42,"domain":"example.test"}'
    shield="$lib.importShield [ $TMPDIR/identity.txt ]"
    actual=$(evalJson "$shield $TMPDIR/fixture.nix.age" | jq -cS .)
    [[ $actual == "$expected" ]] \
      || fail "decrypted value was $actual, expected $expected"

    # A consumer's own extra-builtins file keeps both its additions
    # and importShield when handed to lib.mkNix.
    composed="{
      shield = $shield $TMPDIR/fixture.nix.age;
      consumerAnswer = builtins.extraBuiltins.consumerAnswer;
    }"
    actual=$(${composedNix}/bin/nix eval --store "$store" --json \
      --extra-experimental-features 'nix-command flakes' --impure \
      --expr "$composed" \
      | jq -cS .)
    expected=$(jq -cS . <<'JSON'
    {
      "consumerAnswer": 42,
      "shield": { "answer": 42, "domain": "example.test" }
    }
    JSON
    )
    [[ $actual == "$expected" ]] \
      || fail "composed builtins returned $actual, expected $expected"

    # expectFailure <what> <pattern> <command>...
    expectFailure() {
      local what=$1 pattern=$2
      shift 2
      if "$@" 2> stderr.log; then
        fail "$what: evaluation succeeded"
      fi
      grep -q -- "$pattern" stderr.log \
        || fail "$what: message lacks '$pattern'"
    }

    expectFailure "missing shield file" "$TMPDIR/missing.nix.age" \
      evalJson "$shield $TMPDIR/missing.nix.age"
    expectFailure "empty master identities" "no master identity" \
      evalJson "$lib.importShield [ ] $TMPDIR/fixture.nix.age"

    # The example consumer, evaluated as a flake with its inputs
    # pointed at the sandbox's copies. Pure evaluation reads store
    # paths through the store, so the builtins file must be valid too.
    registerStorePath "$store" "$extraBuiltinsFile"
    registerStorePath "$store" "$nixpkgs"
    registerStorePath "$store" "$flakeParts"
    registerStorePath "$store" "$kit"

    evalExample() {
      nixEval --no-write-lock-file \
        --override-input nixpkgs "path:$nixpkgs" \
        --override-input nixos-shields "path:$kit" \
        --override-input flake-parts "path:$flakeParts" \
        "path:$example#$1"
    }

    expected=$(jq -cS . <<'JSON'
    {
      "configurations": {
        "alpha": { "files": { "facts": "shields/alpha.nix.age" } },
        "beta": { "files": { "facts": "shields/beta.nix.age" } }
      },
      "files": { "shared": "shields/shared.nix.age" },
      "masterIdentities": [ "master-identities/throwaway.txt" ]
    }
    JSON
    )
    actual=$(evalExample shields | jq -cS .)
    [[ $actual == "$expected" ]] \
      || fail "manifest was $actual, expected $expected"

    expected='{"domain":"example.test"}'
    actual=$(evalExample sharedShield | jq -cS .)
    [[ $actual == "$expected" ]] \
      || fail "flake-scoped values were $actual, expected $expected"

    expected=$(jq -cS . <<'JSON'
    {
      "facts": {
        "domain": "alpha.example.test",
        "macAddress": "02:00:00:00:00:01"
      }
    }
    JSON
    )
    actual=$(evalExample nixosConfigurations.alpha.config.age.shields.values \
      | jq -cS .)
    [[ $actual == "$expected" ]] \
      || fail "alpha's shield values were $actual, expected $expected"

    # The value reaches ordinary options of the same configuration.
    actual=$(evalExample nixosConfigurations.alpha.config.networking.domain)
    [[ $actual == '"alpha.example.test"' ]] \
      || fail "alpha's networking.domain was $actual"

    actual=$(evalExample nixosConfigurations.alpha.config.networking.search)
    [[ $actual == '["example.test"]' ]] \
      || fail "flake-scoped values missing from networking.search: $actual"

    expectFailure "configuration without its shield" \
      "shields/beta.nix.age does not exist" \
      evalExample nixosConfigurations.beta.config.age.shields.values

    # The suffix check inspects the base name, so nothing above copied
    # a shield file into the store on its own; the example's source
    # tree is the only place one may appear.
    copies=$(find "$NIX_STORE" -maxdepth 1 -name '*.nix.age')
    [[ -z $copies ]] || fail "shield file copied into the eval store: $copies"

    touch "$out"
  ''
