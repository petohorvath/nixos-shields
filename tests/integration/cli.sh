# cli.nix copies the example to $consumer before sourcing this script.
: "${consumer:?}" "${example:?}"

fail() { echo "FAIL: $*" >&2; exit 1; }

expectFailure() {
  local pattern=$1
  shift
  if "$@" > "$TMPDIR/stdout.log" 2> "$TMPDIR/stderr.log"; then
    fail "command succeeded: $*"
  fi
  grep -q -- "$pattern" "$TMPDIR/stderr.log" \
    || fail "failure did not mention '$pattern': $(cat "$TMPDIR/stderr.log")"
}

# Cleanup is useful even outside a flake and with no manifest available.
mkdir "$TMPDIR/cleanup-fixture"
echo plaintext > "$TMPDIR/cleanup-fixture/shield.nix"
(
  cd "$HOME" || exit
  NIXOS_SHIELDS_CACHE_DIR="$TMPDIR/cleanup-fixture" nixos-shields clean
  NIXOS_SHIELDS_CACHE_DIR="$TMPDIR/cleanup-fixture" nixos-shields clean
)
[[ ! -e $TMPDIR/cleanup-fixture ]] || fail "clean left the override directory behind"
echo keep > "$HOME/keep"
expectFailure 'refusing' env NIXOS_SHIELDS_CACHE_DIR="$HOME" nixos-shields clean
expectFailure 'refusing' env NIXOS_SHIELDS_CACHE_DIR="$TMPDIR" nixos-shields clean
ln -s "$HOME" "$TMPDIR/cache-link"
expectFailure 'refusing' env NIXOS_SHIELDS_CACHE_DIR="$TMPDIR/cache-link" nixos-shields clean
[[ -f $HOME/keep ]] || fail "clean removed unrelated files"
expectFailure 'local directory' nixos-shields --flake github:someone/flake clean

# The example's throwaway identity is a plain age key inside the flake
# root, so every command reading the manifest warns about it on stderr and
# still succeeds.
expectPlaintextKeyWarning() {
  local identity=$1 log=$2
  grep -q "warning: master identity $identity holds an unencrypted private key" "$log" \
    || fail "no plaintext key warning for $identity: $(cat "$log")"
}

# Listing reads declarations even when a configuration's shield is missing.
# Both configurations declare shields/shared.nix.age, so it is listed under
# each of them.
nixos-shields list --json > listing.json 2> "$TMPDIR/list-stderr.log" \
  || fail "list failed beside the plaintext key warning"
expectPlaintextKeyWarning master-identities/throwaway.txt "$TMPDIR/list-stderr.log"
jq -e '(has("files") | not) and .configurations == {
    alpha: {files: {
      facts: {file: "shields/alpha.nix.age", status: "exists"},
      shared: {file: "shields/shared.nix.age", status: "exists"}}},
    beta: {files: {
      facts: {file: "shields/beta.nix.age", status: "missing"},
      shared: {file: "shields/shared.nix.age", status: "exists"}}}}
  and .totals == {total: 4, exists: 3, missing: 1}' listing.json \
  || fail "listing differs from the example's declarations"

nixos-shields list > listing.txt
if grep -q 'Flake-scoped' listing.txt; then fail "listing has a flake-scoped group"; fi
grep -qx 'Configuration alpha:' listing.txt || fail "missing alpha group"
grep -qx 'Configuration beta:' listing.txt || fail "missing beta group"
grep -q 'alpha:shared.*exists' listing.txt || fail "alpha:shared is not listed as existing"
grep -q 'beta:shared.*exists' listing.txt || fail "beta:shared is not listed as existing"
grep -q 'beta:facts.*missing' listing.txt || fail "beta is not listed as missing"
grep -qx 'Total: 4; exists: 3; missing: 1' listing.txt || fail "incorrect text totals"

nixos-shields list --configuration beta --json > filtered.json
jq -e '(has("files") | not) and .configurations == {
    beta: {files: {
      facts: {file: "shields/beta.nix.age", status: "missing"},
      shared: {file: "shields/shared.nix.age", status: "exists"}}}}
  and .totals == {total: 2, exists: 1, missing: 1}' filtered.json \
  || fail "configuration filter included other shields"
nixos-shields list --configuration alpha > filtered.txt
grep -q 'alpha:facts.*exists' filtered.txt || fail "filtered text lacks alpha"
if grep -q 'beta:' filtered.txt; then fail "filtered text includes beta"; fi

(
  cd "$TMPDIR" || exit
  nixos-shields --flake "$consumer" list --json > from-elsewhere.json
)
cmp listing.json "$TMPDIR/from-elsewhere.json" || fail "--flake did not select the consumer"
expectFailure 'unknown configuration' nixos-shields list --configuration absent
expectFailure 'local directory' nixos-shields --flake github:someone/flake list
expectFailure 'local directory' nixos-shields list --flake "path:$consumer"
expectFailure 'local directory' nixos-shields --flake "$example" list

evalExample() {
  nix eval --json --extra-experimental-features 'nix-command flakes' "path:.#$1"
}

# Shield values reach ordinary options of the configuration, and a
# declared missing shield file fails naming its location.
[[ $(evalExample nixosConfigurations.alpha.config.networking.domain) == '"alpha.example.test"' ]] \
  || fail "alpha's networking.domain lacks its shield value"
[[ $(evalExample nixosConfigurations.alpha.config.networking.search) == '["example.test"]' ]] \
  || fail "alpha's networking.search lacks the shared value"
[[ $(evalExample nixosConfigurations.beta.config.age.shields.values.shared) == '{"domain":"example.test"}' ]] \
  || fail "beta cannot read the shared shield beside its missing one"
# Values are readable from outside the configuration, as deploy-rs would.
[[ $(evalExample deploy.nodes.alpha.hostname) == '"alpha.example.test"' ]] \
  || fail "alpha's shield value is not readable from outside it"
expectFailure 'shields/beta.nix.age does not exist' \
  evalExample nixosConfigurations.beta.config.age.shields.values

# Drive the editor as an operator-supplied command, including quoted paths
# and arguments. Its only view of the plaintext is the file passed to it.
export EDITOR_DIRECTORY=$TMPDIR/editor-directory
cat > "$TMPDIR/scripted editor" <<'EDITOR_SCRIPT'
set -euo pipefail
directory=$(dirname "$2")
[[ $(stat -c %a "$directory") == 700 ]]
[[ $(stat -c %a "$2") == 600 ]]
printf '%s\n' "$directory" > "$EDITOR_DIRECTORY"
case $1 in
  unchanged) ;;
  shared) echo '{ domain = "edited.example.test"; }' > "$2" ;;
  empty) [[ $(cat "$2") == '{}' ]] ;;
  beta) echo '{ domain = "beta.example.test"; }' > "$2" ;;
  locked) echo '{ domain = "locked.example.test"; }' > "$2" ;;
  fail) echo '{ broken' > "$2"; exit 42 ;;
esac
EDITOR_SCRIPT

cp shields/shared.nix.age "$TMPDIR/shared-before.age"
EDITOR="bash '$TMPDIR/scripted editor' unchanged" nixos-shields edit alpha:shared \
  2> "$TMPDIR/edit-stderr.log"
expectPlaintextKeyWarning master-identities/throwaway.txt "$TMPDIR/edit-stderr.log"
cmp shields/shared.nix.age "$TMPDIR/shared-before.age" || fail "unchanged edit rewrote the shield"
[[ ! -e $(cat "$EDITOR_DIRECTORY") ]] || fail "unchanged edit left plaintext behind"

# A changed edit must target every master identity: the common module's
# list, now with a backup, and an identity that only alpha declares.
rage-keygen -o master-identities/backup.txt 2>/dev/null
rage-keygen -o master-identities/alpha-only.txt 2>/dev/null
sed -i 's@masterIdentities = \[ ./master-identities/throwaway.txt \];@masterIdentities = [ ./master-identities/throwaway.txt ./master-identities/backup.txt ];@' flake.nix
# mkAfter keeps the common module's identities first in the manifest.
sed -i '/nixpkgs.hostPlatform =/i\                  age.shields.masterIdentities = nixpkgs.lib.mkIf (name == "alpha") (nixpkgs.lib.mkAfter [ ./master-identities/alpha-only.txt ]);' flake.nix
evalExample nixosConfigurations.alpha.config.age.shields.masterIdentities \
  | jq -e 'any(.identity | endswith("alpha-only.txt"))' > /dev/null || fail "alpha lacks its own identity"
evalExample nixosConfigurations.beta.config.age.shields.masterIdentities \
  | jq -e 'any(.identity | endswith("alpha-only.txt")) | not' > /dev/null || fail "beta declares alpha's identity"
# Edited through beta, whose identities exclude alpha's; both read it.
EDITOR="bash '$TMPDIR/scripted editor' shared" nixos-shields edit beta:shared
if cmp -s shields/shared.nix.age "$TMPDIR/shared-before.age"; then fail "changed edit did not encrypt"; fi
for identity in master-identities/throwaway.txt master-identities/backup.txt master-identities/alpha-only.txt; do
  actual=$(rage --decrypt --identity "$identity" shields/shared.nix.age)
  [[ $actual == '{ domain = "edited.example.test"; }' ]] || fail "edit omitted $identity"
done
for name in alpha beta; do
  [[ $(evalExample "nixosConfigurations.$name.config.age.shields.values.shared") == '{"domain":"edited.example.test"}' ]] \
    || fail "wrapped Nix did not read the edited shield through $name"
done
[[ ! -e $(cat "$EDITOR_DIRECTORY") ]] || fail "changed edit left plaintext behind"

# A declared missing file starts empty and is created even without changes.
EDITOR="bash '$TMPDIR/scripted editor' empty" nixos-shields edit beta:facts
[[ $(evalExample nixosConfigurations.beta.config.age.shields.values.facts) == '{}' ]] \
  || fail "new shield did not start as an empty expression"
EDITOR="bash '$TMPDIR/scripted editor' beta" nixos-shields edit beta:facts
[[ $(evalExample nixosConfigurations.beta.config.age.shields.values.facts) == '{"domain":"beta.example.test"}' ]] \
  || fail "edit did not reach beta"
[[ ! -e $(cat "$EDITOR_DIRECTORY") ]] || fail "new shield left plaintext behind"
# alpha's identity opens a shield that only beta declares.
rage --decrypt --identity master-identities/alpha-only.txt shields/beta.nix.age > /dev/null \
  || fail "edit omitted alpha's identity from beta's shield"

cp shields/shared.nix.age "$TMPDIR/shared-before-failure.age"
expectFailure 'editor' env EDITOR="bash '$TMPDIR/scripted editor' fail" nixos-shields edit alpha:shared
cmp shields/shared.nix.age "$TMPDIR/shared-before-failure.age" || fail "failed editor replaced the shield"
[[ ! -e $(cat "$EDITOR_DIRECTORY") ]] || fail "failed editor left plaintext behind"
expectFailure 'unknown address' nixos-shields edit absent
# Every shield belongs to a configuration, so a bare name is no address.
expectFailure 'unknown address' nixos-shields edit shared

# With no explicit identity, rekey decrypts with every master identity, so
# a new first identity that opens no shield yet does not stop it. It also
# includes the backup even on alpha's previously unchanged shield.
rage-keygen -o master-identities/new.txt 2>/dev/null
sed -i 's@\[ ./master-identities/throwaway.txt@[ ./master-identities/new.txt ./master-identities/throwaway.txt@' flake.nix
nixos-shields rekey
for file in shields/*.nix.age; do
  for identity in master-identities/new.txt master-identities/backup.txt master-identities/alpha-only.txt; do
    rage --decrypt --identity "$identity" "$file" > /dev/null \
      || fail "default rekey omitted $identity for $file"
  done
done
[[ $(evalExample nixosConfigurations.alpha.config.networking.domain) == '"alpha.example.test"' ]] \
  || fail "alpha cannot read its shield with its own identity after rekey"

# Keep only the backup in the common module and decrypt with the removed
# throwaway. The shared file has an address in each configuration; rotation
# must encrypt it once, or decrypting it again with the old identity fails.
cp master-identities/throwaway.txt "$TMPDIR/old identity.txt"
sed -i 's@\[ ./master-identities/new.txt ./master-identities/throwaway.txt ./master-identities/backup.txt \]@[ ./master-identities/backup.txt ]@' flake.nix
(
  cd "$TMPDIR" || exit
  nixos-shields --flake "$consumer" rekey --identity 'old identity.txt'
)
for file in shields/*.nix.age; do
  if rage --decrypt --identity master-identities/throwaway.txt "$file" > /dev/null 2>&1; then
    fail "removed identity still opens $file"
  fi
  rage --decrypt --identity master-identities/backup.txt "$file" > /dev/null \
    || fail "new identity cannot open $file"
  rage --decrypt --identity master-identities/alpha-only.txt "$file" > /dev/null \
    || fail "rotation omitted alpha's identity for $file"
done
for name in alpha beta; do
  [[ $(evalExample "nixosConfigurations.$name.config.age.shields.values.shared") == '{"domain":"edited.example.test"}' ]] \
    || fail "rotation changed the shared value read through $name"
done
[[ $(evalExample nixosConfigurations.alpha.config.age.shields.values.facts) == '{"domain":"alpha.example.test","macAddress":"02:00:00:00:00:01"}' ]] \
  || fail "rotation changed alpha's values"
[[ $(evalExample nixosConfigurations.beta.config.age.shields.values.facts) == '{"domain":"beta.example.test"}' ]] \
  || fail "rotation changed beta's values"

# A passphrase-protected identity paired with its public key. Creating it
# answers the passphrase prompt through a scripted pinentry; nothing
# answers it afterwards, so presenting the identity file to rage fails.
cat > "$TMPDIR/pinentry" <<PINENTRY
#!$BASH
echo OK
while IFS= read -r line; do
  case \$line in
    GETPIN*) echo 'D example passphrase' ;;
  esac
  echo OK
  [[ \$line != BYE* ]] || exit 0
done
PINENTRY
chmod +x "$TMPDIR/pinentry"
rage-keygen -o "$TMPDIR/locked key.txt" 2>/dev/null
locked_pubkey=$(rage-keygen -y "$TMPDIR/locked key.txt")
PINENTRY_PROGRAM=$TMPDIR/pinentry rage --passphrase \
  --output master-identities/locked.age "$TMPDIR/locked key.txt" < /dev/null
expectFailure 'encrypted key' rage --encrypt --identity master-identities/locked.age \
  --output "$TMPDIR/presented.age" flake.nix < /dev/null
sed -i "s@\\[ ./master-identities/backup.txt \\]@[ ./master-identities/backup.txt { identity = ./master-identities/locked.age; pubkey = \"$locked_pubkey\"; } ]@" flake.nix
evalExample shields | jq -e --arg pubkey "$locked_pubkey" '.masterIdentities == [
    {identity: "master-identities/backup.txt", pubkey: null},
    {identity: "master-identities/locked.age", pubkey: $pubkey},
    {identity: "master-identities/alpha-only.txt", pubkey: null}]' > /dev/null \
  || fail "the manifest lacks the identity paired with its public key"
EDITOR="bash '$TMPDIR/scripted editor' locked" nixos-shields edit alpha:shared < /dev/null
[[ $(rage --decrypt --identity "$TMPDIR/locked key.txt" shields/shared.nix.age) == '{ domain = "locked.example.test"; }' ]] \
  || fail "edit did not encrypt to the public key paired with the locked identity"
nixos-shields rekey < /dev/null
for file in shields/*.nix.age; do
  rage --decrypt --identity "$TMPDIR/locked key.txt" "$file" > /dev/null \
    || fail "the public key paired with the locked identity cannot open $file"
done
[[ $(evalExample nixosConfigurations.beta.config.age.shields.values.shared) == '{"domain":"locked.example.test"}' ]] \
  || fail "beta cannot read the shared shield beside the locked identity"

# The primary identity need not be declared, and is relative to the caller.
# With _ONLY, it alone decrypts: the removed identity fails, a copy of the
# declared one succeeds.
cp master-identities/backup.txt "$TMPDIR/primary.txt"
cp shields/alpha.nix.age "$TMPDIR/alpha-before-primary.age"
expectFailure 'No matching keys found' env NIXOS_SHIELDS_PRIMARY_IDENTITY="$TMPDIR/old identity.txt" \
  NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY=true EDITOR="bash '$TMPDIR/scripted editor' unchanged" \
  nixos-shields edit alpha:facts
(
  cd "$TMPDIR" || exit
  NIXOS_SHIELDS_PRIMARY_IDENTITY=primary.txt NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY=true \
    EDITOR="bash '$TMPDIR/scripted editor' unchanged" nixos-shields --flake "$consumer" edit alpha:facts
)
cmp shields/alpha.nix.age "$TMPDIR/alpha-before-primary.age" || fail "primary identity edit rewrote the shield"
expectFailure 'NIXOS_SHIELDS_PRIMARY_IDENTITY' env NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY=true \
  EDITOR="bash '$TMPDIR/scripted editor' unchanged" nixos-shields edit alpha:facts

# Without _ONLY, the declared identities follow a primary that fails.
NIXOS_SHIELDS_PRIMARY_IDENTITY="$TMPDIR/old identity.txt" \
  EDITOR="bash '$TMPDIR/scripted editor' unchanged" nixos-shields edit alpha:facts

# Evaluation honours the same variables. Each run starts with a cold decrypt
# cache and no evaluation cache, so it really decrypts.
evalWithPrimaryOnly() {
  local primary=$1 cache
  cache=$(mktemp -d "$TMPDIR/primary-cache.XXXXXX")
  NIXOS_SHIELDS_CACHE_DIR=$cache NIXOS_SHIELDS_PRIMARY_IDENTITY=$primary \
    NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY=true \
    nix eval --json --no-eval-cache --extra-experimental-features 'nix-command flakes' \
    path:.#nixosConfigurations.alpha.config.networking.domain
}
expectFailure 'No matching keys found' evalWithPrimaryOnly "$TMPDIR/old identity.txt"
[[ $(evalWithPrimaryOnly "$TMPDIR/primary.txt") == '"alpha.example.test"' ]] \
  || fail "evaluation did not decrypt with the primary identity"

# A plain key outside the flake root, given as an absolute path string,
# stays absolute in the manifest and is found from any working directory.
outside_identity="$TMPDIR/outside identities/outside-identity.txt"
mkdir -p "$(dirname "$outside_identity")"
rage-keygen -o "$outside_identity" 2>/dev/null
sed -i "s@\\[ ./master-identities/backup.txt@[ \"$outside_identity\" ./master-identities/backup.txt@" flake.nix
evalExample shields | jq -e --arg identity "$outside_identity" \
  '.masterIdentities[0] == {identity: $identity, pubkey: null}' > /dev/null \
  || fail "the manifest does not keep the outside identity absolute"
(
  cd "$TMPDIR" || exit
  nixos-shields --flake "$consumer" rekey < /dev/null
)
for file in shields/*.nix.age; do
  rage --decrypt --identity "$outside_identity" "$file" > /dev/null \
    || fail "rekey omitted the outside identity for $file"
done

# With the outside identity the only one with a file on disk, edit, rekey,
# and evaluation decrypt with it alone. A teammate's identity paired with
# its public key need not exist, as nothing presents its file.
rage-keygen -o "$TMPDIR/teammate.txt" 2>/dev/null
teammate_pubkey=$(rage-keygen -y "$TMPDIR/teammate.txt")
sed -i '/alpha-only.txt/d' flake.nix
sed -i "s@masterIdentities = \\[ \"$outside_identity\" .*\\];@masterIdentities = [ \"$outside_identity\" { identity = \"$TMPDIR/absent/teammate.txt\"; pubkey = \"$teammate_pubkey\"; } ];@" flake.nix
evalExample shields | jq -e --arg identity "$outside_identity" --arg pubkey "$teammate_pubkey" \
  --arg teammate "$TMPDIR/absent/teammate.txt" '.masterIdentities == [
    {identity: $identity, pubkey: null}, {identity: $teammate, pubkey: $pubkey}]' > /dev/null \
  || fail "the manifest does not declare only the outside identities"
EDITOR="bash '$TMPDIR/scripted editor' shared" nixos-shields edit alpha:shared
[[ $(rage --decrypt --identity "$outside_identity" shields/shared.nix.age) == '{ domain = "edited.example.test"; }' ]] \
  || fail "edit with the outside identity did not encrypt to it"
if rage --decrypt --identity master-identities/backup.txt shields/shared.nix.age > /dev/null 2>&1; then
  fail "edit still encrypted to an identity no longer declared"
fi
(
  cd "$TMPDIR" || exit
  nixos-shields --flake "$consumer" rekey
)
for file in shields/*.nix.age; do
  for identity in "$outside_identity" "$TMPDIR/teammate.txt"; do
    rage --decrypt --identity "$identity" "$file" > /dev/null \
      || fail "rekey with the outside identity omitted $identity for $file"
  done
done
outside_cache=$(mktemp -d "$TMPDIR/outside-cache.XXXXXX")
[[ $(NIXOS_SHIELDS_CACHE_DIR=$outside_cache nix eval --json --no-eval-cache \
  --extra-experimental-features 'nix-command flakes' \
  path:.#nixosConfigurations.beta.config.age.shields.values.shared) == '{"domain":"edited.example.test"}' ]] \
  || fail "evaluation did not decrypt with the outside identity"

# Neither the outside identity nor the absent teammate's earns a warning.
nixos-shields list > /dev/null 2> "$TMPDIR/outside-stderr.log"
if grep -q 'warning: master identity' "$TMPDIR/outside-stderr.log"; then
  fail "warned about an identity outside the flake root: $(cat "$TMPDIR/outside-stderr.log")"
fi

# Inside the flake root, an unencrypted OpenSSH key warns, while a YubiKey
# stub, the passphrase-protected age identity, and a passphrase-protected
# OpenSSH key do not. Only list runs, as encrypting to a YubiKey needs its
# plugin.
cp flake.nix "$TMPDIR/flake-before-inside-identities.nix"
cat > master-identities/yubikey.txt <<'STUB'
#    Recipient: age1yubikey1qwpx8z4xg2cqnjztq8s0hyum7c3g6dc2zc6t6r4ykhxkk0wp7hm6y5zskw2
AGE-PLUGIN-YUBIKEY-1QXQPZ9TAZNG7SEQXYXR5XJ
STUB
ssh-keygen -q -t ed25519 -N '' -C '' -f master-identities/ssh-plain
ssh-keygen -q -t ed25519 -N 'example passphrase' -C '' -f master-identities/ssh-locked
sed -i "s@masterIdentities = \\[ \"$outside_identity\"@masterIdentities = [ ./master-identities/yubikey.txt { identity = ./master-identities/locked.age; pubkey = \"$locked_pubkey\"; } ./master-identities/ssh-locked ./master-identities/ssh-plain \"$outside_identity\"@" flake.nix
evalExample shields | jq -e '[.masterIdentities[].identity] | index("master-identities/ssh-plain") != null' > /dev/null \
  || fail "the manifest lacks the identities inside the flake root"
nixos-shields list > /dev/null 2> "$TMPDIR/inside-stderr.log" \
  || fail "list failed beside the plaintext key warning"
expectPlaintextKeyWarning master-identities/ssh-plain "$TMPDIR/inside-stderr.log"
for identity in yubikey.txt locked.age ssh-locked; do
  if grep -q "master identity master-identities/$identity " "$TMPDIR/inside-stderr.log"; then
    fail "warned about master-identities/$identity: $(cat "$TMPDIR/inside-stderr.log")"
  fi
done
cp "$TMPDIR/flake-before-inside-identities.nix" flake.nix

# The suffix check inspects the base name, so no evaluation above copied
# a shield file into the store on its own; the consumer's source tree is
# the only place one may appear. The outside identity appears nowhere.
copies=$(find "$NIX_STORE" -maxdepth 1 -name '*.nix.age' -o -name '*outside-identity*')
[[ -z $copies ]] || fail "shield file or outside identity copied into the store: $copies"

[[ -n $(find "$NIXOS_SHIELDS_CACHE_DIR" -type f -print -quit) ]] \
  || fail "wrapped evaluation did not populate the decrypt cache"
nixos-shields clean
[[ ! -e $NIXOS_SHIELDS_CACHE_DIR ]] || fail "clean left the evaluation's decrypt cache behind"
