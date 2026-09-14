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
  cd "$HOME"
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
nixos-shields list --json > listing.json
jq -e '.files == {shared: {file: "shields/shared.nix.age", status: "exists"}}
  and .configurations == {
    alpha: {files: {facts: {file: "shields/alpha.nix.age", status: "exists"}}},
    beta: {files: {facts: {file: "shields/beta.nix.age", status: "missing"}}}}
  and .totals == {total: 3, exists: 2, missing: 1}' listing.json \
  || fail "listing differs from the example's declarations"

nixos-shields list > listing.txt
grep -qx 'Flake-scoped shields:' listing.txt || fail "missing flake scope"
grep -qx 'Configuration-scoped shields (alpha):' listing.txt || fail "missing alpha scope"
grep -qx 'Configuration-scoped shields (beta):' listing.txt || fail "missing beta scope"
grep -q 'shared.*exists' listing.txt || fail "shared is not listed as existing"
grep -q 'beta:facts.*missing' listing.txt || fail "beta is not listed as missing"
grep -qx 'Total: 3; exists: 2; missing: 1' listing.txt || fail "incorrect text totals"

nixos-shields list --configuration beta --json > filtered.json
jq -e '.files == {} and .configurations == {
    beta: {files: {facts: {file: "shields/beta.nix.age", status: "missing"}}}}
  and .totals == {total: 1, exists: 0, missing: 1}' filtered.json \
  || fail "configuration filter included other shields"
nixos-shields list --configuration alpha > filtered.txt
grep -q 'alpha:facts.*exists' filtered.txt || fail "filtered text lacks alpha"
if grep -Eq 'shared|beta:facts' filtered.txt; then fail "filtered text includes other scopes"; fi

(
  cd "$TMPDIR"
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
EDITOR="bash '$TMPDIR/scripted editor' unchanged" nixos-shields edit shared
cmp shields/shared.nix.age "$TMPDIR/shared-before.age" || fail "unchanged edit rewrote the shield"
[[ ! -e $(cat "$EDITOR_DIRECTORY") ]] || fail "unchanged edit left plaintext behind"

# A changed edit must target every master identity, including the backup.
rage-keygen -o master-identities/backup.txt 2>/dev/null
sed -i 's@masterIdentities = \[ ./master-identities/throwaway.txt \];@masterIdentities = [ ./master-identities/throwaway.txt ./master-identities/backup.txt ];@' flake.nix
EDITOR="bash '$TMPDIR/scripted editor' shared" nixos-shields edit shared
if cmp -s shields/shared.nix.age "$TMPDIR/shared-before.age"; then fail "changed edit did not encrypt"; fi
for identity in master-identities/throwaway.txt master-identities/backup.txt; do
  actual=$(rage --decrypt --identity "$identity" shields/shared.nix.age)
  [[ $actual == '{ domain = "edited.example.test"; }' ]] || fail "edit omitted $identity"
done
[[ $(evalExample sharedShield) == '{"domain":"edited.example.test"}' ]] \
  || fail "wrapped Nix did not read the edited shield"
[[ ! -e $(cat "$EDITOR_DIRECTORY") ]] || fail "changed edit left plaintext behind"

# A declared missing file starts empty and is created even without changes.
EDITOR="bash '$TMPDIR/scripted editor' empty" nixos-shields edit beta:facts
[[ $(evalExample nixosConfigurations.beta.config.age.shields.values) == '{"facts":{}}' ]] \
  || fail "new shield did not start as an empty expression"
EDITOR="bash '$TMPDIR/scripted editor' beta" nixos-shields edit beta:facts
[[ $(evalExample nixosConfigurations.beta.config.age.shields.values) == '{"facts":{"domain":"beta.example.test"}}' ]] \
  || fail "configuration-scoped edit did not reach the configuration"
[[ ! -e $(cat "$EDITOR_DIRECTORY") ]] || fail "new shield left plaintext behind"

cp shields/shared.nix.age "$TMPDIR/shared-before-failure.age"
expectFailure 'editor' env EDITOR="bash '$TMPDIR/scripted editor' fail" nixos-shields edit shared
cmp shields/shared.nix.age "$TMPDIR/shared-before-failure.age" || fail "failed editor replaced the shield"
[[ ! -e $(cat "$EDITOR_DIRECTORY") ]] || fail "failed editor left plaintext behind"
expectFailure 'unknown address' nixos-shields edit absent

# With no explicit identity, rekey uses the first master identity and
# includes the backup even on alpha's previously unchanged shield.
nixos-shields rekey
for file in shields/*.nix.age; do
  rage --decrypt --identity master-identities/backup.txt "$file" > /dev/null \
    || fail "default rekey omitted the backup for $file"
done

# Remove the first identity from the declaration and use it only to decrypt.
# A file can have multiple addresses; rotation must encrypt that file once.
cp master-identities/throwaway.txt "$TMPDIR/old identity.txt"
sed -i 's@\[ ./master-identities/throwaway.txt ./master-identities/backup.txt \]@[ ./master-identities/backup.txt ]@' flake.nix
sed -i '/files.shared =/a\          files.sharedAlias = ./shields/shared.nix.age;' flake.nix
(
  cd "$TMPDIR"
  nixos-shields --flake "$consumer" rekey --identity 'old identity.txt'
)
for file in shields/*.nix.age; do
  if rage --decrypt --identity master-identities/throwaway.txt "$file" > /dev/null 2>&1; then
    fail "removed identity still opens $file"
  fi
  rage --decrypt --identity master-identities/backup.txt "$file" > /dev/null \
    || fail "new identity cannot open $file"
done
[[ $(evalExample sharedShield) == '{"domain":"edited.example.test"}' ]] \
  || fail "rotation changed the flake-scoped values"
[[ $(evalExample nixosConfigurations.alpha.config.age.shields.values) == '{"facts":{"domain":"alpha.example.test","macAddress":"02:00:00:00:00:01"}}' ]] \
  || fail "rotation changed alpha's values"
[[ $(evalExample nixosConfigurations.beta.config.age.shields.values) == '{"facts":{"domain":"beta.example.test"}}' ]] \
  || fail "rotation changed beta's values"

[[ -n $(find "$NIXOS_SHIELDS_CACHE_DIR" -type f -print -quit) ]] \
  || fail "wrapped evaluation did not populate the decrypt cache"
nixos-shields clean
[[ ! -e $NIXOS_SHIELDS_CACHE_DIR ]] || fail "clean left the evaluation's decrypt cache behind"
