# shellcheck shell=bash
# cli.nix copies the example to $consumer before sourcing this script.
: "${consumer:?}" "${example:?}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expectFailure() {
  local pattern=$1
  shift
  if "$@" >"$TMPDIR/stdout.log" 2>"$TMPDIR/stderr.log"; then
    fail "command succeeded: $*"
  fi
  grep -q -- "$pattern" "$TMPDIR/stderr.log" ||
    fail "failure did not mention '$pattern': $(cat "$TMPDIR/stderr.log")"
}

# Evaluation shares one decrypt cache. Every run of the tool that names
# none gets a cold one of its own, so a decryption it asserts on is never
# served by an entry that an evaluation or an earlier run left behind.
evaluation_cache=$TMPDIR/decrypt-cache
mkdir "$TMPDIR/cold-cache-bin"
cat >"$TMPDIR/cold-cache-bin/nixos-shields" <<WRAPPER
#!$BASH
[[ -n \${NIXOS_SHIELDS_CACHE_DIR:-} ]] ||
  export NIXOS_SHIELDS_CACHE_DIR=\$(mktemp -d "$TMPDIR/cli-cache.XXXXXX")
exec $(command -v nixos-shields) "\$@"
WRAPPER
chmod +x "$TMPDIR/cold-cache-bin/nixos-shields"
export PATH=$TMPDIR/cold-cache-bin:$PATH

# Cleanup is useful even outside a flake and with no manifest available.
# The decrypt script refuses an unsafe directory; the tool adds the
# selected flake to the directories it protects.
mkdir "$TMPDIR/cleanup-fixture"
echo plaintext >"$TMPDIR/cleanup-fixture/shield.nix"
(
  cd "$HOME" || exit
  NIXOS_SHIELDS_CACHE_DIR="$TMPDIR/cleanup-fixture" nixos-shields clean
  expectFailure 'refusing' env NIXOS_SHIELDS_CACHE_DIR="$consumer" nixos-shields --flake "$consumer" clean
)
[[ ! -e $TMPDIR/cleanup-fixture ]] || fail "clean left the override directory behind"
[[ -f flake.nix ]] || fail "clean removed the selected flake"
expectFailure 'local directory' nixos-shields --flake github:someone/flake clean

# The example's throwaway identity is a plain age key inside the flake
# root, so every command reading the manifest warns about it on stderr and
# still succeeds.
expectPlaintextKeyWarning() {
  local identity=$1 log=$2
  grep -q "warning: master identity $identity holds an unencrypted private key" "$log" ||
    fail "no plaintext key warning for $identity: $(cat "$log")"
}

# Listing reads declarations even when a configuration's shield is missing.
# Both configurations declare shields/shared.nix.age, so it is listed under
# each of them.
nixos-shields list --json >listing.json 2>"$TMPDIR/list-stderr.log" ||
  fail "list failed beside the plaintext key warning"
expectPlaintextKeyWarning master-identities/throwaway.txt "$TMPDIR/list-stderr.log"
jq -e '(has("files") | not) and .configurations == {
    alpha: {files: {
      facts: {file: "shields/alpha.nix.age", status: "exists"},
      shared: {file: "shields/shared.nix.age", status: "exists"}}},
    beta: {files: {
      facts: {file: "shields/beta.nix.age", status: "missing"},
      shared: {file: "shields/shared.nix.age", status: "exists"}}}}
  and .totals == {total: 4, exists: 3, missing: 1}' listing.json ||
  fail "listing differs from the example's declarations"

nixos-shields list >listing.txt
if grep -q 'Flake-scoped' listing.txt; then fail "listing has a flake-scoped group"; fi
grep -qx 'Configuration alpha:' listing.txt || fail "missing alpha group"
grep -qx 'Configuration beta:' listing.txt || fail "missing beta group"
grep -q 'alpha:shared.*exists' listing.txt || fail "alpha:shared is not listed as existing"
grep -q 'beta:shared.*exists' listing.txt || fail "beta:shared is not listed as existing"
grep -q 'beta:facts.*missing' listing.txt || fail "beta is not listed as missing"
grep -qx 'Total: 4; exists: 3; missing: 1' listing.txt || fail "incorrect text totals"

nixos-shields list --configuration beta --json >filtered.json
jq -e '(has("files") | not) and .configurations == {
    beta: {files: {
      facts: {file: "shields/beta.nix.age", status: "missing"},
      shared: {file: "shields/shared.nix.age", status: "exists"}}}}
  and .totals == {total: 2, exists: 1, missing: 1}' filtered.json ||
  fail "configuration filter included other shields"
nixos-shields list --configuration alpha >filtered.txt
grep -q 'alpha:facts.*exists' filtered.txt || fail "filtered text lacks alpha"
if grep -q 'beta:' filtered.txt; then fail "filtered text includes beta"; fi

(
  cd "$TMPDIR" || exit
  nixos-shields --flake "$consumer" list --json >from-elsewhere.json
)
cmp listing.json "$TMPDIR/from-elsewhere.json" || fail "--flake did not select the consumer"
expectFailure 'unknown configuration' nixos-shields list --configuration absent
expectFailure 'local directory' nixos-shields --flake github:someone/flake list
expectFailure 'local directory' nixos-shields list --flake "path:$consumer"
expectFailure 'local directory' nixos-shields --flake "$example" list

evalExample() {
  NIXOS_SHIELDS_CACHE_DIR=$evaluation_cache \
    nix eval --json --extra-experimental-features 'nix-command flakes' "path:.#$1"
}

# Shield values reach ordinary options of the configuration, and a
# declared missing shield file fails naming its location.
[[ $(evalExample nixosConfigurations.alpha.config.networking.domain) == '"alpha.example.test"' ]] ||
  fail "alpha's networking.domain lacks its shield value"
[[ $(evalExample nixosConfigurations.alpha.config.networking.search) == '["example.test"]' ]] ||
  fail "alpha's networking.search lacks the shared value"
[[ $(evalExample nixosConfigurations.beta.config.age.shields.values.shared) == '{"domain":"example.test"}' ]] ||
  fail "beta cannot read the shared shield beside its missing one"
# Values are readable from outside the configuration, as deploy-rs would.
[[ $(evalExample deploy.nodes.alpha.hostname) == '"alpha.example.test"' ]] ||
  fail "alpha's shield value is not readable from outside it"
expectFailure 'shields/beta.nix.age does not exist' \
  evalExample nixosConfigurations.beta.config.age.shields.values

# Drive the editor as an operator-supplied command, including quoted paths
# and arguments. Its only view of the plaintext is the file passed to it.
export EDITOR_DIRECTORY=$TMPDIR/editor-directory
cat >"$TMPDIR/scripted editor" <<'EDITOR_SCRIPT'
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
  stubs) echo '{ domain = "stubs.example.test"; }' > "$2" ;;
  binary) echo '{ domain = "binary.example.test"; }' > "$2" ;;
  fail) echo '{ broken' > "$2"; exit 42 ;;
esac
EDITOR_SCRIPT

cp shields/shared.nix.age "$TMPDIR/shared-before.age"
EDITOR="bash '$TMPDIR/scripted editor' unchanged" nixos-shields edit alpha:shared \
  2>"$TMPDIR/edit-stderr.log"
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
evalExample nixosConfigurations.alpha.config.age.shields.masterIdentities |
  jq -e 'any(.identity | endswith("alpha-only.txt"))' >/dev/null || fail "alpha lacks its own identity"
evalExample nixosConfigurations.beta.config.age.shields.masterIdentities |
  jq -e 'any(.identity | endswith("alpha-only.txt")) | not' >/dev/null || fail "beta declares alpha's identity"
# Edited through beta, whose identities exclude alpha's; both read it.
EDITOR="bash '$TMPDIR/scripted editor' shared" nixos-shields edit beta:shared
if cmp -s shields/shared.nix.age "$TMPDIR/shared-before.age"; then fail "changed edit did not encrypt"; fi
for identity in master-identities/throwaway.txt master-identities/backup.txt master-identities/alpha-only.txt; do
  actual=$(rage --decrypt --identity "$identity" shields/shared.nix.age)
  [[ $actual == '{ domain = "edited.example.test"; }' ]] || fail "edit omitted $identity"
done
for name in alpha beta; do
  [[ $(evalExample "nixosConfigurations.$name.config.age.shields.values.shared") == '{"domain":"edited.example.test"}' ]] ||
    fail "wrapped Nix did not read the edited shield through $name"
done
[[ ! -e $(cat "$EDITOR_DIRECTORY") ]] || fail "changed edit left plaintext behind"

# A declared missing file starts empty and is created even without changes.
EDITOR="bash '$TMPDIR/scripted editor' empty" nixos-shields edit beta:facts
[[ $(evalExample nixosConfigurations.beta.config.age.shields.values.facts) == '{}' ]] ||
  fail "new shield did not start as an empty expression"
EDITOR="bash '$TMPDIR/scripted editor' beta" nixos-shields edit beta:facts
[[ $(evalExample nixosConfigurations.beta.config.age.shields.values.facts) == '{"domain":"beta.example.test"}' ]] ||
  fail "edit did not reach beta"
[[ ! -e $(cat "$EDITOR_DIRECTORY") ]] || fail "new shield left plaintext behind"
# alpha's identity opens a shield that only beta declares.
rage --decrypt --identity master-identities/alpha-only.txt shields/beta.nix.age >/dev/null ||
  fail "edit omitted alpha's identity from beta's shield"

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
    rage --decrypt --identity "$identity" "$file" >/dev/null ||
      fail "default rekey omitted $identity for $file"
  done
done
[[ $(evalExample nixosConfigurations.alpha.config.networking.domain) == '"alpha.example.test"' ]] ||
  fail "alpha cannot read its shield with its own identity after rekey"

# Keep only the backup in the common module and decrypt with the removed
# throwaway. The shared file has an address in each configuration; rotation
# must encrypt it once, or decrypting it again with the old identity fails.
cp master-identities/throwaway.txt "$TMPDIR/old identity.txt"
sed -i 's@\[ ./master-identities/new.txt ./master-identities/throwaway.txt ./master-identities/backup.txt \]@[ ./master-identities/backup.txt ]@' flake.nix
# The explicit identity decrypts alone: the declared backup, which opens
# every shield, is not tried beside one that opens none.
rage-keygen -o "$TMPDIR/stranger.txt" 2>/dev/null
expectFailure 'No matching keys found' nixos-shields rekey --identity "$TMPDIR/stranger.txt"
(
  cd "$TMPDIR" || exit
  nixos-shields --flake "$consumer" rekey --identity 'old identity.txt'
)
for file in shields/*.nix.age; do
  if rage --decrypt --identity master-identities/throwaway.txt "$file" >/dev/null 2>&1; then
    fail "removed identity still opens $file"
  fi
  rage --decrypt --identity master-identities/backup.txt "$file" >/dev/null ||
    fail "new identity cannot open $file"
  rage --decrypt --identity master-identities/alpha-only.txt "$file" >/dev/null ||
    fail "rotation omitted alpha's identity for $file"
done
for name in alpha beta; do
  [[ $(evalExample "nixosConfigurations.$name.config.age.shields.values.shared") == '{"domain":"edited.example.test"}' ]] ||
    fail "rotation changed the shared value read through $name"
done
[[ $(evalExample nixosConfigurations.alpha.config.age.shields.values.facts) == '{"domain":"alpha.example.test","macAddress":"02:00:00:00:00:01"}' ]] ||
  fail "rotation changed alpha's values"
[[ $(evalExample nixosConfigurations.beta.config.age.shields.values.facts) == '{"domain":"beta.example.test"}' ]] ||
  fail "rotation changed beta's values"

# A passphrase-protected identity paired with its public key. Creating it
# answers the passphrase prompt through a scripted pinentry; nothing
# answers it afterwards, so presenting the identity file to rage fails.
cat >"$TMPDIR/pinentry" <<PINENTRY
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
  --output master-identities/locked.age "$TMPDIR/locked key.txt" </dev/null
expectFailure 'encrypted key' rage --encrypt --identity master-identities/locked.age \
  --output "$TMPDIR/presented.age" flake.nix </dev/null
sed -i "s@\\[ ./master-identities/backup.txt \\]@[ ./master-identities/backup.txt { identity = ./master-identities/locked.age; pubkey = \"$locked_pubkey\"; } ]@" flake.nix
evalExample shields | jq -e --arg pubkey "$locked_pubkey" '.masterIdentities == [
    {identity: "master-identities/backup.txt", pubkey: null},
    {identity: "master-identities/locked.age", pubkey: $pubkey},
    {identity: "master-identities/alpha-only.txt", pubkey: null}]' >/dev/null ||
  fail "the manifest lacks the identity paired with its public key"
EDITOR="bash '$TMPDIR/scripted editor' locked" nixos-shields edit alpha:shared </dev/null
[[ $(rage --decrypt --identity "$TMPDIR/locked key.txt" shields/shared.nix.age) == '{ domain = "locked.example.test"; }' ]] ||
  fail "edit did not encrypt to the public key paired with the locked identity"
nixos-shields rekey </dev/null
for file in shields/*.nix.age; do
  rage --decrypt --identity "$TMPDIR/locked key.txt" "$file" >/dev/null ||
    fail "the public key paired with the locked identity cannot open $file"
done
[[ $(evalExample nixosConfigurations.beta.config.age.shields.values.shared) == '{"domain":"locked.example.test"}' ]] ||
  fail "beta cannot read the shared shield beside the locked identity"

# The primary identity need not be declared, and is relative to the caller.
# With _ONLY, a copy of the declared one decrypts alone.
cp master-identities/backup.txt "$TMPDIR/primary.txt"
cp shields/alpha.nix.age "$TMPDIR/alpha-before-primary.age"
(
  cd "$TMPDIR" || exit
  NIXOS_SHIELDS_PRIMARY_IDENTITY=primary.txt NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY=true \
    EDITOR="bash '$TMPDIR/scripted editor' unchanged" nixos-shields --flake "$consumer" edit alpha:facts
)
cmp shields/alpha.nix.age "$TMPDIR/alpha-before-primary.age" || fail "primary identity edit rewrote the shield"

# The tool reads shields through the decrypt cache, so one an evaluation
# unlocked opens for edit with only an identity that cannot decrypt it.
NIXOS_SHIELDS_CACHE_DIR=$evaluation_cache nix eval --json --no-eval-cache \
  --extra-experimental-features 'nix-command flakes' \
  path:.#nixosConfigurations.alpha.config.networking.domain >/dev/null
NIXOS_SHIELDS_CACHE_DIR=$evaluation_cache NIXOS_SHIELDS_PRIMARY_IDENTITY="$TMPDIR/old identity.txt" \
  NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY=true EDITOR="bash '$TMPDIR/scripted editor' unchanged" \
  nixos-shields edit alpha:facts ||
  fail "edit did not read the shield the evaluation cached"
cmp shields/alpha.nix.age "$TMPDIR/alpha-before-primary.age" || fail "cached edit rewrote the shield"

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
[[ $(evalWithPrimaryOnly "$TMPDIR/primary.txt") == '"alpha.example.test"' ]] ||
  fail "evaluation did not decrypt with the primary identity"

# A plain key outside the flake root, given as an absolute path string,
# stays absolute in the manifest and is found from any working directory.
outside_identity="$TMPDIR/outside identities/outside-identity.txt"
mkdir -p "$(dirname "$outside_identity")"
rage-keygen -o "$outside_identity" 2>/dev/null
sed -i "s@\\[ ./master-identities/backup.txt@[ \"$outside_identity\" ./master-identities/backup.txt@" flake.nix
evalExample shields | jq -e --arg identity "$outside_identity" \
  '.masterIdentities[0] == {identity: $identity, pubkey: null}' >/dev/null ||
  fail "the manifest does not keep the outside identity absolute"
(
  cd "$TMPDIR" || exit
  nixos-shields --flake "$consumer" rekey </dev/null
)
for file in shields/*.nix.age; do
  rage --decrypt --identity "$outside_identity" "$file" >/dev/null ||
    fail "rekey omitted the outside identity for $file"
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
    {identity: $identity, pubkey: null}, {identity: $teammate, pubkey: $pubkey}]' >/dev/null ||
  fail "the manifest does not declare only the outside identities"
EDITOR="bash '$TMPDIR/scripted editor' shared" nixos-shields edit alpha:shared
[[ $(rage --decrypt --identity "$outside_identity" shields/shared.nix.age) == '{ domain = "edited.example.test"; }' ]] ||
  fail "edit with the outside identity did not encrypt to it"
if rage --decrypt --identity master-identities/backup.txt shields/shared.nix.age >/dev/null 2>&1; then
  fail "edit still encrypted to an identity no longer declared"
fi
(
  cd "$TMPDIR" || exit
  nixos-shields --flake "$consumer" rekey
)
for file in shields/*.nix.age; do
  for identity in "$outside_identity" "$TMPDIR/teammate.txt"; do
    rage --decrypt --identity "$identity" "$file" >/dev/null ||
      fail "rekey with the outside identity omitted $identity for $file"
  done
done
outside_cache=$(mktemp -d "$TMPDIR/outside-cache.XXXXXX")
[[ $(NIXOS_SHIELDS_CACHE_DIR=$outside_cache nix eval --json --no-eval-cache \
  --extra-experimental-features 'nix-command flakes' \
  path:.#nixosConfigurations.beta.config.age.shields.values.shared) == '{"domain":"edited.example.test"}' ]] ||
  fail "evaluation did not decrypt with the outside identity"

# Neither the outside identity nor the absent teammate's earns a warning.
nixos-shields list >/dev/null 2>"$TMPDIR/outside-stderr.log"
if grep -q 'warning: master identity' "$TMPDIR/outside-stderr.log"; then
  fail "warned about an identity outside the flake root: $(cat "$TMPDIR/outside-stderr.log")"
fi

# Encryption reads the public key of a YubiKey or FIDO2 identity stub that
# no configuration pairs with one, inside the flake root or outside it; the
# manifest leaves its pubkey null. No age plugin is on PATH, so presenting
# a stub to rage fails. A FIDO2 stub whose comment holds an X25519 public
# key, which only its private key opens, shows that encryption used the
# comment's key. The outside identity alone decrypts, as the primary
# identity, so no stub is presented for decryption.
cp flake.nix "$TMPDIR/flake-before-stubs.nix"
fido2_identity_line=AGE-PLUGIN-FIDO2-HMAC-1QU2ZZT3MFP2KYMMU3XT28V9AETT7FU07PVVZ2V3LF3VKVUUQ3KDQUMTPZ7
# Writes a FIDO2 stub to $1 with a public key comment for each further key.
writeFido2Stub() {
  local file=$1 key
  shift
  {
    echo '# created: 2026-10-15T09:00:00Z'
    for key in "$@"; do echo "# public key: $key"; done
    echo "$fido2_identity_line"
  } >"$file"
}
for name in fido2 comment declared outside; do
  rage-keygen -o "$TMPDIR/$name key.txt" 2>/dev/null
done
pubkeyOf() { rage-keygen -y "$TMPDIR/$1 key.txt"; }
outside_stub="$TMPDIR/outside identities/fido2.txt"
writeFido2Stub master-identities/fido2.txt "$(pubkeyOf fido2)"
writeFido2Stub master-identities/fido2-declared.txt "$(pubkeyOf comment)"
writeFido2Stub "$outside_stub" "$(pubkeyOf outside)"
expectFailure "Could not find 'age-plugin-fido2-hmac'" rage --encrypt \
  --identity master-identities/fido2.txt --output "$TMPDIR/presented.age" flake.nix
declared_pubkey=$(pubkeyOf declared)
sed -i "s@masterIdentities = \\[ \"$outside_identity\"@masterIdentities = [ ./master-identities/fido2.txt { identity = ./master-identities/fido2-declared.txt; pubkey = \"$declared_pubkey\"; } \"$outside_stub\" \"$outside_identity\"@" flake.nix
evalExample shields | jq -e --arg stub "$outside_stub" --arg pubkey "$declared_pubkey" '
    .masterIdentities[0:3] == [
      {identity: "master-identities/fido2.txt", pubkey: null},
      {identity: "master-identities/fido2-declared.txt", pubkey: $pubkey},
      {identity: $stub, pubkey: null}]' >/dev/null ||
  fail "the manifest does not leave undeclared stub public keys null"
# Edits alpha:shared with editor case $1, decrypting with the outside
# identity alone; further arguments are environment assignments.
editAsOutsideIdentity() {
  local editor_case=$1
  shift
  env "$@" NIXOS_SHIELDS_PRIMARY_IDENTITY="$outside_identity" NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY=true \
    EDITOR="bash '$TMPDIR/scripted editor' $editor_case" nixos-shields edit alpha:shared
}
editAsOutsideIdentity stubs
for name in fido2 declared outside; do
  [[ $(rage --decrypt --identity "$TMPDIR/$name key.txt" shields/shared.nix.age) == '{ domain = "stubs.example.test"; }' ]] ||
    fail "edit did not encrypt to the $name stub's public key"
done
if rage --decrypt --identity "$TMPDIR/comment key.txt" shields/shared.nix.age >/dev/null 2>&1; then
  fail "the stub's comment won over its declared public key"
fi

# A stub with no public key, or with several, is presented as it is, so
# encrypting to it needs the absent plugin and leaves the shield unchanged.
cp shields/shared.nix.age "$TMPDIR/shared-before-fallback.age"
writeFido2Stub master-identities/fido2.txt
expectFailure "Could not find 'age-plugin-fido2-hmac'" editAsOutsideIdentity binary
writeFido2Stub master-identities/fido2.txt "$(pubkeyOf fido2)" "$(pubkeyOf comment)"
expectFailure "Could not find 'age-plugin-fido2-hmac'" editAsOutsideIdentity binary
cmp shields/shared.nix.age "$TMPDIR/shared-before-fallback.age" ||
  fail "a failed fallback encryption replaced the shield"

# Encrypting even to a YubiKey stub's public key needs its plugin, so a
# stand-in plugin records whether rage gave it the stub's recipient or its
# identity line, and then fails.
yubikey_identity_line=AGE-PLUGIN-YUBIKEY-1PCDJSD2ZFAWXJA5RJZW64D7Y680WKDV3Z36
yubikey_recipient=age1yubikey1z53z70zf2e3hqlv2j7jtr0ktmrjl9lcvrynrxszdtfnhfqvwnw5t2d3xvz8
mkdir "$TMPDIR/plugins"
cat >"$TMPDIR/plugins/age-plugin-yubikey" <<PLUGIN
#!$BASH
while IFS= read -r line; do
  case \$line in
    '-> add-'*) echo "\${line#-> }" >> "$TMPDIR/yubikey-plugin.log" ;;
    '-> done') exit 1 ;;
  esac
done
PLUGIN
chmod +x "$TMPDIR/plugins/age-plugin-yubikey"
sed -i 's@\./master-identities/fido2\.txt@./master-identities/yubikey.txt@' flake.nix
yubikeyPluginRequests() {
  rm -f "$TMPDIR/yubikey-plugin.log"
  expectFailure 'age-plugin-yubikey' editAsOutsideIdentity binary PATH="$TMPDIR/plugins:$PATH"
  cat "$TMPDIR/yubikey-plugin.log"
}
cat >master-identities/yubikey.txt <<STUB
#       Serial: 12345678, Slot: 1
#    Recipient: $yubikey_recipient
$yubikey_identity_line
STUB
[[ $(yubikeyPluginRequests) == "add-recipient $yubikey_recipient" ]] ||
  fail "edit did not encrypt to the YubiKey stub's recipient"
sed -i '/Recipient:/d' master-identities/yubikey.txt
[[ $(yubikeyPluginRequests) == "add-identity $yubikey_identity_line" ]] ||
  fail "edit did not present the YubiKey stub without a recipient"

# Nix cannot read a file holding a NUL byte, yet a binary
# passphrase-protected identity inside the flake root, given without its
# public key, leaves the manifest intact. Encryption presents it, asking
# for its passphrase, without noise about the binary file.
holdsNul() { [[ $(tr -cd '\0' <"$1" | wc -c) -gt 0 ]]; }
until [[ -f master-identities/binary.age ]] && holdsNul master-identities/binary.age; do
  rm -f master-identities/binary.age
  PINENTRY_PROGRAM=$TMPDIR/pinentry rage --passphrase \
    --output master-identities/binary.age "$TMPDIR/locked key.txt" </dev/null
done
cp "$TMPDIR/flake-before-stubs.nix" flake.nix
sed -i "s@masterIdentities = \\[ \"$outside_identity\"@masterIdentities = [ ./master-identities/binary.age \"$outside_identity\"@" flake.nix
nixos-shields list >/dev/null 2>"$TMPDIR/binary-stderr.log" ||
  fail "list failed beside a binary identity: $(cat "$TMPDIR/binary-stderr.log")"
evalExample shields | jq -e '.masterIdentities[0] == {identity: "master-identities/binary.age", pubkey: null}' >/dev/null ||
  fail "the manifest does not leave the binary identity's public key null"
editAsOutsideIdentity binary PINENTRY_PROGRAM="$TMPDIR/pinentry" </dev/null 2>"$TMPDIR/binary-stderr.log"
if grep -q -i -e binary -e 'null byte' "$TMPDIR/binary-stderr.log"; then
  fail "encryption reported on the binary identity: $(cat "$TMPDIR/binary-stderr.log")"
fi
[[ $(rage --decrypt --identity "$TMPDIR/locked key.txt" shields/shared.nix.age) == '{ domain = "binary.example.test"; }' ]] ||
  fail "edit did not encrypt to the binary identity"
cp "$TMPDIR/flake-before-stubs.nix" flake.nix

# Inside the flake root, an unencrypted OpenSSH key warns, while a YubiKey
# stub, the passphrase-protected age identity, and a passphrase-protected
# OpenSSH key do not. Only list runs, as encrypting to a YubiKey needs its
# plugin.
cp flake.nix "$TMPDIR/flake-before-inside-identities.nix"
cat >master-identities/yubikey.txt <<'STUB'
#    Recipient: age1yubikey1qwpx8z4xg2cqnjztq8s0hyum7c3g6dc2zc6t6r4ykhxkk0wp7hm6y5zskw2
AGE-PLUGIN-YUBIKEY-1QXQPZ9TAZNG7SEQXYXR5XJ
STUB
ssh-keygen -q -t ed25519 -N '' -C '' -f master-identities/ssh-plain
ssh-keygen -q -t ed25519 -N 'example passphrase' -C '' -f master-identities/ssh-locked
sed -i "s@masterIdentities = \\[ \"$outside_identity\"@masterIdentities = [ ./master-identities/yubikey.txt { identity = ./master-identities/locked.age; pubkey = \"$locked_pubkey\"; } ./master-identities/ssh-locked ./master-identities/ssh-plain \"$outside_identity\"@" flake.nix
evalExample shields | jq -e '[.masterIdentities[].identity] | index("master-identities/ssh-plain") != null' >/dev/null ||
  fail "the manifest lacks the identities inside the flake root"
nixos-shields list >/dev/null 2>"$TMPDIR/inside-stderr.log" ||
  fail "list failed beside the plaintext key warning"
expectPlaintextKeyWarning master-identities/ssh-plain "$TMPDIR/inside-stderr.log"
for identity in yubikey.txt locked.age ssh-locked; do
  if grep -q "master identity master-identities/$identity " "$TMPDIR/inside-stderr.log"; then
    fail "warned about master-identities/$identity: $(cat "$TMPDIR/inside-stderr.log")"
  fi
done
cp "$TMPDIR/flake-before-inside-identities.nix" flake.nix

# Extra encryption pubkeys: alpha declares a backup key as a public key,
# beta a team's recipients file inside the flake. Every shield is encrypted
# to both, combined in the manifest. Their private keys lie where nothing
# can use them, and passing either entry to rage as an identity fails, so
# edit and rekey succeeding shows that decryption never needs them.
rage-keygen -o "$TMPDIR/backup key.txt" 2>/dev/null
backup_pubkey=$(rage-keygen -y "$TMPDIR/backup key.txt")
rage-keygen -o "$TMPDIR/team key.txt" 2>/dev/null
{
  echo '# The team'
  rage-keygen -y "$TMPDIR/team key.txt"
} >team-recipients.txt
sed -i "/nixpkgs.hostPlatform =/i\\                  age.shields.extraEncryptionPubkeys = if name == \"alpha\" then [ \"$backup_pubkey\" ] else [ ./team-recipients.txt ];" flake.nix
evalExample shields | jq -e --arg pubkey "$backup_pubkey" '
    .extraEncryptionPubkeys == [{pubkey: $pubkey}, {recipientsFile: "team-recipients.txt"}]
    and (.masterIdentities | length == 2)' >/dev/null ||
  fail "the manifest does not combine the extra encryption pubkeys"
EDITOR="bash '$TMPDIR/scripted editor' locked" nixos-shields edit alpha:shared
for key in "$TMPDIR/backup key.txt" "$TMPDIR/team key.txt"; do
  [[ $(rage --decrypt --identity "$key" shields/shared.nix.age) == '{ domain = "locked.example.test"; }' ]] ||
    fail "edit did not encrypt to the extra encryption pubkey of $key"
done
nixos-shields rekey
for file in shields/*.nix.age; do
  for key in "$TMPDIR/backup key.txt" "$TMPDIR/team key.txt" "$outside_identity"; do
    rage --decrypt --identity "$key" "$file" >/dev/null ||
      fail "rekey omitted $key for $file"
  done
done
extra_cache=$(mktemp -d "$TMPDIR/extra-cache.XXXXXX")
[[ $(NIXOS_SHIELDS_CACHE_DIR=$extra_cache nix eval --json --no-eval-cache \
  --extra-experimental-features 'nix-command flakes' \
  path:.#nixosConfigurations.beta.config.age.shields.values.shared) == '{"domain":"locked.example.test"}' ]] ||
  fail "evaluation did not decrypt beside the extra encryption pubkeys"

# The suffix check inspects the base name, so no evaluation above copied
# a shield file into the store on its own; the consumer's source tree is
# the only place one may appear. The outside identity appears nowhere.
copies=$(find "$NIX_STORE" -maxdepth 1 -name '*.nix.age' -o -name '*outside-identity*')
[[ -z $copies ]] || fail "shield file or outside identity copied into the store: $copies"

[[ -n $(find "$evaluation_cache" -type f -print -quit) ]] ||
  fail "wrapped evaluation did not populate the decrypt cache"
NIXOS_SHIELDS_CACHE_DIR=$evaluation_cache nixos-shields clean
[[ ! -e $evaluation_cache ]] || fail "clean left the evaluation's decrypt cache behind"
