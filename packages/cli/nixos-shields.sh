die() { echo "nixos-shields: $*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: nixos-shields [--flake <directory>] <command>
  list [--json] [--configuration <name>]
  edit <address>                         Edit with $EDITOR
  rekey [--identity <file>]               Encrypt to all master identities
  clean                                 Remove the user's decrypt cache
USAGE
}

flake=.
flake_given=false
configuration=
rekey_identity=
json=false
positional=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --flake|--configuration|--identity)
      [[ $# -ge 2 && -n $2 ]] || die "$1 requires a value"
      case $1 in
        --flake) flake=$2; flake_given=true ;;
        --configuration) configuration=$2 ;;
        --identity) rekey_identity=$2 ;;
      esac
      shift 2
      ;;
    --json) json=true; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; positional+=("$@"); break ;;
    -*) die "unknown option: $1" ;;
    *) positional+=("$1"); shift ;;
  esac
done
[[ ${#positional[@]} -gt 0 ]] || die "expected a command; see --help"
command_name=${positional[0]}
case $command_name in
  list) [[ ${#positional[@]} == 1 ]] || die "list takes no address" ;;
  edit)
    [[ ${#positional[@]} == 2 ]] || die "edit requires one address"
    ;;
  rekey|clean) [[ ${#positional[@]} == 1 ]] || die "$command_name takes no address" ;;
  *) die "unknown command: $command_name; see --help" ;;
esac
[[ $command_name == list || ( $json == false && -z $configuration ) ]] \
  || die "--json and --configuration are for list"
[[ $command_name == rekey || -z $rekey_identity ]] || die "--identity is for rekey"

flake_dir=
if [[ $command_name != clean || $flake_given == true ]]; then
  [[ -d $flake ]] || die "--flake must be a local directory: $flake"
  flake_dir=$(realpath -e -- "$flake")
  case $flake_dir in
    /nix/store|/nix/store/*) die "--flake must be a local directory outside /nix/store: $flake" ;;
  esac
  [[ -f $flake_dir/flake.nix ]] || die "no flake.nix in $flake_dir"
fi

if [[ $command_name == clean ]]; then
  cache_dir=${NIXOS_SHIELDS_CACHE_DIR:-/var/tmp/nixos-shields-$UID}
  [[ ! -L $cache_dir ]] || die "refusing to remove a decrypt cache symlink: $cache_dir"
  if [[ ! -e $cache_dir ]]; then
    echo "Decrypt cache already empty: $cache_dir"
    exit 0
  fi
  [[ -d $cache_dir && -O $cache_dir ]] \
    || die "refusing to remove a decrypt cache that is not a directory owned by the current user: $cache_dir"
  cache_dir=$(realpath -e -- "$cache_dir")
  case $cache_dir in
    /nix/store|/nix/store/*) die "refusing to remove a decrypt cache in /nix/store" ;;
  esac
  # An accidental override such as /, ~ or . must not erase unrelated files.
  for protected in / "${HOME:-}" "$(pwd -P)" "$flake_dir"; do
    [[ -n $protected ]] || continue
    protected=$(realpath -m -- "$protected")
    [[ $protected != "$cache_dir" && $protected != "$cache_dir/"* ]] \
      || die "refusing to remove a decrypt cache containing $protected: $cache_dir"
  done
  rm -rf -- "$cache_dir"
  echo "Removed decrypt cache: $cache_dir"
  exit 0
fi

# Resolve against the checkout, including symlinks, before reading or writing.
resolve_file() {
  local file
  [[ -n $1 && $1 != /* ]] || die "manifest file must be relative to the flake: $1"
  file=$(realpath -m -- "$flake_dir/$1")
  [[ $file == "$flake_dir/"* ]] || die "manifest file is outside the flake: $1"
  echo "$file"
}

manifest=$(
  cd "$flake_dir" || exit
  nix eval --json --extra-experimental-features 'nix-command flakes' \
    --no-write-lock-file 'path:.#shields'
)

if [[ -n $configuration ]]; then
  jq -e --arg name "$configuration" '.configurations | has($name)' <<< "$manifest" > /dev/null \
    || die "unknown configuration: $configuration"
  manifest=$(jq --arg name "$configuration" '
    .files = {} | .configurations |= with_entries(select(.key == $name))
  ' <<< "$manifest")
fi

shields=$(jq '[
  (.files | to_entries[] |
    {address: .key, configuration: null, name: .key, file: .value}),
  (.configurations | to_entries[] | .key as $configuration |
    .value.files | to_entries[] |
    {address: ($configuration + ":" + .key), configuration: $configuration,
      name: .key, file: .value})
]' <<< "$manifest")

if [[ $command_name == list ]]; then
  listing=$(
    while IFS= read -r shield; do
      file=$(resolve_file "$(jq -r .file <<< "$shield")") || exit
      status=missing
      [[ ! -f $file ]] || status=exists
      jq --arg status "$status" '. + {status: $status}' <<< "$shield"
    done < <(jq -c '.[]' <<< "$shields") \
      | jq -s --argjson configurations "$(jq '.configurations | map_values({files: {}})' <<< "$manifest")" '
        reduce .[] as $shield ({files: {}, configurations: $configurations};
          {file: $shield.file, status: $shield.status} as $entry |
          if $shield.configuration == null then .files[$shield.name] = $entry
          else .configurations[$shield.configuration].files[$shield.name] = $entry end
        ) as $groups |
        $groups + {totals: {total: length,
          exists: (map(select(.status == "exists")) | length),
          missing: (map(select(.status == "missing")) | length)}}
      '
  )

  if [[ $json == true ]]; then
    echo "$listing"
  else
    jq -r '
      (if (.files | length) > 0 then
        "Flake-scoped shields:",
        (.files | to_entries[] | "  \(.key) [\(.value.status)] \(.value.file)")
      else empty end),
      (.configurations | to_entries[] |
        "Configuration-scoped shields (\(.key)):",
        (.key as $configuration | .value.files | to_entries[] |
          "  \($configuration):\(.key) [\(.value.status)] \(.value.file)")),
      "Total: \(.totals.total); exists: \(.totals.exists); missing: \(.totals.missing)"
    ' <<< "$listing"
  fi
  exit 0
fi

if [[ $command_name == edit ]]; then
  address=${positional[1]}
  shield=$(jq -ce --arg address "$address" '
    map(select(.address == $address)) | if length == 1 then .[0] else empty end
  ' <<< "$shields") || die "unknown address (or ambiguous declaration): $address"
  file=$(resolve_file "$(jq -r .file <<< "$shield")")
  [[ ! -e $file || -f $file ]] || die "not a regular shield file: $file"
  [[ -n ${EDITOR:-} ]] || die "set EDITOR to the editor command to run"
fi

identity_args=()
while IFS= read -r -d '' identity; do
  identity=$(resolve_file "$identity")
  [[ -f $identity ]] || die "master identity does not exist: $identity"
  identity_args+=(--identity "$identity")
done < <(jq -j '.masterIdentities[] | ., "\u0000"' <<< "$manifest")
[[ ${#identity_args[@]} -gt 0 ]] || die "no master identity declared"

if [[ $command_name == rekey ]]; then
  # An explicit identity is relative to the caller, not the flake directory.
  rekey_identity=${rekey_identity:-${identity_args[1]}}
  [[ -f $rekey_identity ]] || die "decryption identity does not exist: $rekey_identity"
  files=()
  declare -A seen_files=()
  while IFS= read -r -d '' relative; do
    file=$(resolve_file "$relative")
    [[ -f $file ]] || die "shield file does not exist: $file; create it with edit first"
    if [[ -z ${seen_files[$file]+present} ]]; then
      files+=("$file")
      seen_files[$file]=true
    fi
  done < <(jq -j '.[].file | ., "\u0000"' <<< "$shields")
fi

umask 077
workdir=
ciphertext=
cleanup() {
  if [[ -n $ciphertext ]]; then rm -f -- "$ciphertext"; fi
  if [[ -n $workdir ]]; then rm -rf -- "$workdir"; fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
workdir=$(mktemp -d "${TMPDIR:-/tmp}/nixos-shields.XXXXXX")
case $(realpath -- "$workdir") in
  "$flake_dir/"*) die "temporary directory must be outside the flake; set TMPDIR" ;;
esac
plaintext=$workdir/shield.nix

# Encrypt beside the destination, then atomically replace it. A failed
# encryption cannot truncate the original, and the EXIT trap removes partials.
encrypt_file() {
  local destination=$1
  mkdir -p -- "$(dirname "$destination")"
  ciphertext=$(mktemp "$(dirname "$destination")/.nixos-shields.XXXXXX")
  rage --encrypt "${identity_args[@]}" --output "$ciphertext" "$plaintext"
  mv -f -- "$ciphertext" "$destination"
  ciphertext=
}

if [[ $command_name == rekey ]]; then
  for file in "${files[@]}"; do
    rage --decrypt --identity "$rekey_identity" --output "$plaintext" "$file"
    encrypt_file "$file"
    echo "Rekeyed: ${file#"$flake_dir/"}"
  done
  exit 0
fi

existing=false
if [[ -f $file ]]; then
  existing=true
  rage --decrypt "${identity_args[@]}" --output "$plaintext" "$file"
else
  echo '{}' > "$plaintext"
fi
cp "$plaintext" "$workdir/original.nix"
bash -c "$EDITOR \"\$@\"" nixos-shields-editor "$plaintext" \
  || die "editor failed; shield left unchanged"
[[ -f $plaintext ]] || die "editor removed the plaintext file; shield left unchanged"
if [[ $existing == true ]] && cmp -s "$plaintext" "$workdir/original.nix"; then
  echo "Unchanged: $address"
  exit 0
fi

encrypt_file "$file"
echo "Saved: $address"
