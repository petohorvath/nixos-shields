/*
  The cache script driven directly, without Nix in the loop (the pure
  tier of the spec's testing decisions). The script's PATH is fixed by
  writeShellApplication, so the decryptor is observed by building the
  script against a counting wrapper around rage rather than by
  shadowing rage on the check's own PATH.
*/
{
  runCommand,
  writeShellScriptBin,
  callPackage,
  rage,
}:
let
  # Records every invocation, then behaves exactly like rage.
  countingRage = writeShellScriptBin "rage" ''
    echo >> "$RAGE_CALLS"
    exec ${rage}/bin/rage "$@"
  '';

  decrypt = callPackage ../../packages/decrypt { rage = countingRage; };
in
runCommand "nixos-shields-decrypt-cache"
  {
    nativeBuildInputs = [
      decrypt
      rage
    ];
  }
  ''
    cd "$TMPDIR"
    export RAGE_CALLS=$TMPDIR/rage-calls
    export NIXOS_SHIELDS_CACHE_DIR=$TMPDIR/cache
    touch "$RAGE_CALLS"

    fail() { echo "FAIL: $*" >&2; exit 1; }

    calls() { wc -l < "$RAGE_CALLS"; }

    expectCalls() {
      local expected=$1 what=$2
      [[ $(calls) == "$expected" ]] \
        || fail "$what: rage invoked $(calls) times, expected $expected"
    }

    encrypt() {
      local plaintext=$1 file=$2
      echo "$plaintext" > plain.nix
      rage --encrypt --identity identity.txt --output "$file" plain.nix
      rm plain.nix
    }

    rage-keygen -o identity.txt 2>/dev/null
    first='{ domain = "first.test"; }'
    second='{ domain = "second.test"; }'
    encrypt "$first" shield.nix.age

    # Miss: the first call decrypts and prints the plaintext.
    actual=$(nixos-shields-decrypt shield.nix.age identity.txt)
    [[ $actual == "$first" ]] || fail "miss: printed '$actual'"
    expectCalls 1 "miss"

    # Hit: the same file is served from the cache, rage untouched.
    actual=$(nixos-shields-decrypt shield.nix.age identity.txt)
    [[ $actual == "$first" ]] || fail "hit: printed '$actual'"
    expectCalls 1 "hit"

    # The entry is keyed by content, so a copy elsewhere is a hit too.
    mkdir copy
    cp shield.nix.age copy/
    actual=$(nixos-shields-decrypt copy/shield.nix.age identity.txt)
    [[ $actual == "$first" ]] || fail "copied file: printed '$actual'"
    expectCalls 1 "copied file"

    # print-out-path names the entry, and reads as a hit too.
    entry=$(nixos-shields-decrypt --print-out-path shield.nix.age identity.txt)
    [[ $entry == "$NIXOS_SHIELDS_CACHE_DIR"/* ]] \
      || fail "print-out-path: '$entry' is outside the cache directory"
    [[ $(cat "$entry") == "$first" ]] \
      || fail "print-out-path: entry holds '$(cat "$entry")'"
    expectCalls 1 "print-out-path"

    # A changed file gets its own entry; the old one is left in place.
    encrypt "$second" shield.nix.age
    actual=$(nixos-shields-decrypt shield.nix.age identity.txt)
    [[ $actual == "$second" ]] || fail "changed file: printed '$actual'"
    expectCalls 2 "changed file"
    [[ $(cat "$entry") == "$first" ]] \
      || fail "changed file: old entry overwritten"
    entries=$(find "$NIXOS_SHIELDS_CACHE_DIR" -type f | wc -l)
    [[ $entries == 2 ]] \
      || fail "changed file: $entries entries in the cache, expected 2"

    # The override moves the directory: a fresh one starts cold.
    export NIXOS_SHIELDS_CACHE_DIR=$TMPDIR/elsewhere
    entry=$(nixos-shields-decrypt --print-out-path shield.nix.age identity.txt)
    [[ $entry == "$TMPDIR"/elsewhere/* ]] \
      || fail "override: entry '$entry' is not under the override"
    expectCalls 3 "override"
    [[ $(cat "$entry") == "$second" ]] \
      || fail "override: entry holds '$(cat "$entry")'"
    entries=$(find "$TMPDIR/cache" -type f | wc -l)
    [[ $entries == 2 ]] \
      || fail "override: the old directory grew to $entries entries"

    touch "$out"
  ''
