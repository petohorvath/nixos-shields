/*
  The cache script driven directly, without Nix in the loop (the pure
  tier of the spec's testing decisions): the decrypt cache, the identities
  it decrypts with, and its removal. The script's PATH is fixed by
  writeShellApplication, so the decryptor is observed by building the
  script against a counting wrapper around rage rather than by
  shadowing rage on the check's own PATH.
*/
{ inputs, pkgs }:
let
  # Records every invocation, then behaves exactly like rage.
  countingRage = pkgs.writeShellScriptBin "rage" ''
    echo >> "$RAGE_CALLS"
    exec ${pkgs.rage}/bin/rage "$@"
  '';

  decrypt = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.decrypt.override {
    rage = countingRage;
  };

  # rage starts an age plugin only on reaching its identity, so this
  # stand-in records each start and then fails, as no YubiKey answers.
  yubikeyPlugin = pkgs.writeShellScriptBin "age-plugin-yubikey" ''
    echo started >> "$PLUGIN_STARTS"
    while IFS= read -r line; do
      [[ $line != '-> done' ]] || exit 1
    done
  '';
in
pkgs.runCommand "nixos-shields-decrypt-cache"
  {
    nativeBuildInputs = [
      decrypt
      pkgs.rage
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

    expectFailure() {
      local pattern=$1
      shift
      if "$@" > "$TMPDIR/stdout.log" 2> "$TMPDIR/stderr.log"; then
        fail "command succeeded: $*"
      fi
      grep -q -- "$pattern" "$TMPDIR/stderr.log" \
        || fail "failure did not mention '$pattern':" \
          "$(cat "$TMPDIR/stderr.log")"
    }

    # Each identity case starts with a cold decrypt cache of its own, so it
    # really decrypts.
    coldDecryptCache() { export NIXOS_SHIELDS_CACHE_DIR=$TMPDIR/cache-$1; }
    rage-keygen -o stranger.txt 2>/dev/null

    # An identity file that does not exist, such as a teammate's, is skipped;
    # with none left, decryption fails naming the shield file.
    coldDecryptCache absent
    actual=$(nixos-shields-decrypt shield.nix.age absent.txt identity.txt)
    [[ $actual == "$second" ]] || fail "absent identity: printed '$actual'"
    coldDecryptCache none
    expectFailure 'no master identity file exists to decrypt shield.nix.age' \
      nixos-shields-decrypt shield.nix.age absent.txt

    # The given identities follow a primary identity that cannot decrypt.
    coldDecryptCache fallback
    actual=$(NIXOS_SHIELDS_PRIMARY_IDENTITY=stranger.txt \
      nixos-shields-decrypt shield.nix.age identity.txt)
    [[ $actual == "$second" ]] || fail "primary fallback: printed '$actual'"

    # The primary identity is tried before the given ones, so a hardware
    # identity behind one that decrypts is never prompted. A YubiKey stub
    # given first starts the stand-in plugin, which shows it would be.
    echo AGE-PLUGIN-YUBIKEY-1PCDJSD2ZFAWXJA5RJZW64D7Y680WKDV3Z36 > yubikey.txt
    export PLUGIN_STARTS=$TMPDIR/plugin-starts
    touch "$PLUGIN_STARTS"
    pluginStarts() { wc -l < "$PLUGIN_STARTS"; }
    withPlugin() { PATH="${yubikeyPlugin}/bin:$PATH" "$@"; }
    coldDecryptCache stub-first
    expectFailure 'age-plugin-yubikey' withPlugin \
      nixos-shields-decrypt shield.nix.age yubikey.txt identity.txt
    [[ $(pluginStarts) == 1 ]] \
      || fail "stub first: plugin started $(pluginStarts) times, expected 1"
    : > "$PLUGIN_STARTS"
    coldDecryptCache primary-first
    actual=$(NIXOS_SHIELDS_PRIMARY_IDENTITY=identity.txt withPlugin \
      nixos-shields-decrypt shield.nix.age yubikey.txt) \
      || fail "primary first: decryption failed after" \
        "$(pluginStarts) plugin starts"
    [[ $actual == "$second" ]] || fail "primary first: printed '$actual'"
    [[ $(pluginStarts) == 0 ]] \
      || fail "primary first: the stub's plugin started before the primary"

    # With _ONLY, the primary identity alone decrypts, relative to the
    # caller, even when no given identity exists.
    mkdir caller
    cp identity.txt caller/primary.txt
    coldDecryptCache only
    actual=$(cd caller && NIXOS_SHIELDS_PRIMARY_IDENTITY=primary.txt \
      NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY=true \
      nixos-shields-decrypt "$TMPDIR/shield.nix.age" absent.txt)
    [[ $actual == "$second" ]] || fail "primary only: printed '$actual'"
    coldDecryptCache only-stranger
    expectFailure 'No matching keys found' \
      env NIXOS_SHIELDS_PRIMARY_IDENTITY=stranger.txt \
      NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY=true \
      nixos-shields-decrypt shield.nix.age identity.txt
    # A failed decryption leaves neither an entry nor a partial file behind.
    [[ -z $(find "$NIXOS_SHIELDS_CACHE_DIR" -mindepth 1 -print -quit) ]] \
      || fail "failed decryption left in the decrypt cache:" \
        "$(ls -A "$NIXOS_SHIELDS_CACHE_DIR")"
    expectFailure 'IDENTITY_ONLY requires NIXOS_SHIELDS_PRIMARY_IDENTITY' \
      env NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY=true \
      nixos-shields-decrypt shield.nix.age identity.txt
    expectFailure 'primary identity does not exist: absent.txt' \
      env NIXOS_SHIELDS_PRIMARY_IDENTITY=absent.txt \
      nixos-shields-decrypt shield.nix.age identity.txt

    # The variables choose identities only on a miss, not the decrypt cache
    # key: the entry the absent identity case left serves a hit.
    export NIXOS_SHIELDS_CACHE_DIR=$TMPDIR/cache-absent
    actual=$(NIXOS_SHIELDS_PRIMARY_IDENTITY=stranger.txt \
      NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY=true \
      nixos-shields-decrypt shield.nix.age identity.txt)
    [[ $actual == "$second" ]] \
      || fail "hit with primary only: printed '$actual'"

    # --clean removes the decrypt cache with its entries; one already
    # removed is no error.
    export HOME=$TMPDIR/home
    mkdir -p "$HOME"
    echo keep > "$HOME/keep"
    export NIXOS_SHIELDS_CACHE_DIR=$TMPDIR/cache
    nixos-shields-decrypt --clean
    [[ ! -e $TMPDIR/cache ]] || fail "clean left the decrypt cache behind"
    [[ $(nixos-shields-decrypt --clean) == *"already empty"* ]] \
      || fail "clean of a removed decrypt cache did not report it empty"

    # An accidental override must not erase unrelated files: --clean refuses
    # a symlink and a directory containing /, the home directory, the
    # current directory, or a directory it is given. Each case below can
    # trip only its own refusal.
    refusesClean() {
      expectFailure 'refusing' env NIXOS_SHIELDS_CACHE_DIR="$1" \
        nixos-shields-decrypt --clean "''${@:2}"
    }
    refusesClean "$HOME"
    ln -s "$TMPDIR/elsewhere" cache-link
    refusesClean "$TMPDIR/cache-link"
    mkdir -p working/directory
    (cd working/directory && refusesClean "$TMPDIR/working")
    mkdir -p guarded/flake
    refusesClean "$TMPDIR/guarded" "$TMPDIR/guarded/flake"
    [[ -f $HOME/keep && -d working/directory && -d guarded/flake ]] \
      || fail "clean removed unrelated files"

    touch "$out"
  ''
