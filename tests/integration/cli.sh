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

# Listing reads declarations even when a configuration's shield is missing.
# Both configurations declare shields/shared.nix.age, so it is listed under
# each of them.
nixos-shields list --json > listing.json
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
  fail) echo '{ broken' > "$2"; exit 42 ;;
esac
EDITOR_SCRIPT

cp shields/shared.nix.age "$TMPDIR/shared-before.age"
EDITOR="bash '$TMPDIR/scripted editor' unchanged" nixos-shields edit alpha:shared
cmp shields/shared.nix.age "$TMPDIR/shared-before.age" || fail "unchanged edit rewrote the shield"
[[ ! -e $(cat "$EDITOR_DIRECTORY") ]] || fail "unchanged edit left plaintext behind"

# A changed edit must target every master identity: the common module's
# list, now with a backup, and an identity that only alpha declares.
rage-keygen -o master-identities/backup.txt 2>/dev/null
rage-keygen -o master-identities/alpha-only.txt 2>/dev/null
sed -i 's@masterIdentities = \[ ./master-identities/throwaway.txt \];@masterIdentities = [ ./master-identities/throwaway.txt ./master-identities/backup.txt ];@' flake.nix
# mkAfter keeps the throwaway identity first in the manifest, which rekey
# decrypts with by default; alpha.nix.age is not yet encrypted to alpha's.
sed -i '/nixpkgs.hostPlatform =/i\                  age.shields.masterIdentities = nixpkgs.lib.mkIf (name == "alpha") (nixpkgs.lib.mkAfter [ ./master-identities/alpha-only.txt ]);' flake.nix
evalExample nixosConfigurations.alpha.config.age.shields.masterIdentities \
  | jq -e 'any(endswith("alpha-only.txt"))' > /dev/null || fail "alpha lacks its own identity"
evalExample nixosConfigurations.beta.config.age.shields.masterIdentities \
  | jq -e 'any(endswith("alpha-only.txt")) | not' > /dev/null || fail "beta declares alpha's identity"
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

# With no explicit identity, rekey uses the first master identity and
# includes the backup even on alpha's previously unchanged shield.
nixos-shields rekey
for file in shields/*.nix.age; do
  rage --decrypt --identity master-identities/backup.txt "$file" > /dev/null \
    || fail "default rekey omitted the backup for $file"
  rage --decrypt --identity master-identities/alpha-only.txt "$file" > /dev/null \
    || fail "default rekey omitted alpha's identity for $file"
done
[[ $(evalExample nixosConfigurations.alpha.config.networking.domain) == '"alpha.example.test"' ]] \
  || fail "alpha cannot read its shield with its own identity after rekey"

# Remove the first identity from the declaration and use it only to decrypt.
# The shared file has an address in each configuration; rotation must
# encrypt it once, or decrypting it again with the old identity fails.
cp master-identities/throwaway.txt "$TMPDIR/old identity.txt"
sed -i 's@\[ ./master-identities/throwaway.txt ./master-identities/backup.txt \]@[ ./master-identities/backup.txt ]@' flake.nix
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

# The suffix check inspects the base name, so no evaluation above copied
# a shield file into the store on its own; the consumer's source tree is
# the only place one may appear.
copies=$(find "$NIX_STORE" -maxdepth 1 -name '*.nix.age')
[[ -z $copies ]] || fail "shield file copied into the store: $copies"

[[ -n $(find "$NIXOS_SHIELDS_CACHE_DIR" -type f -print -quit) ]] \
  || fail "wrapped evaluation did not populate the decrypt cache"
nixos-shields clean
[[ ! -e $NIXOS_SHIELDS_CACHE_DIR ]] || fail "clean left the evaluation's decrypt cache behind"
