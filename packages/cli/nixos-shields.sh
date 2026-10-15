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

# An identity outside the checkout, such as a key under the home
# directory, is absolute in the manifest; one inside it is relative.
resolve_identity() {
  if [[ $1 == /* ]]; then
    realpath -m -- "$1"
  else
    resolve_file "$1"
  fi
}

manifest=$(
  cd "$flake_dir" || exit
  nix eval --json --extra-experimental-features 'nix-command flakes' \
    --no-write-lock-file 'path:.#shields'
)

# An age secret key line, or an OpenSSH private key whose cipher is none:
# its binary form starts with "openssh-key-v1", a NUL, and the cipher name
# as a length-prefixed string.
unencrypted_openssh_header=$(printf 'openssh-key-v1\0\0\0\0\4none' | od -An -tx1 | tr -d ' \n')
holds_plaintext_key() {
  local line openssh=false body=
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    case $line in
      AGE-SECRET-KEY-*) return 0 ;;
      '-----BEGIN OPENSSH PRIVATE KEY-----') openssh=true ;;
      '-----END OPENSSH PRIVATE KEY-----') break ;;
      *) [[ $openssh == false ]] || body+=$line ;;
    esac
  done < "$1"
  [[ -n $body ]] || return 1
  [[ $(base64 -d <<< "$body" 2> /dev/null | head -c 23 | od -An -tx1 | tr -d ' \n') \
    == "$unencrypted_openssh_header" ]]
}

# A master identity inside the flake root is committed with it and copied
# into the Nix store, so a plain private key there earns a warning. One
# outside the root, or absent, is not inspected.
while IFS= read -r -d '' identity; do
  file=$(realpath -m -- "$flake_dir/$identity")
  [[ -f $file && -r $file ]] || continue
  if holds_plaintext_key "$file"; then
    echo "nixos-shields: warning: master identity $identity holds an unencrypted private key" \
      "inside the flake, which is copied into the Nix store; use a YubiKey or FIDO2 identity" \
      "stub, a passphrase-protected identity, or a path outside the flake" >&2
  fi
done < <(jq -j '.masterIdentities[].identity | select(startswith("/") | not) | ., "\u0000"' <<< "$manifest")

if [[ -n $configuration ]]; then
  jq -e --arg name "$configuration" '.configurations | has($name)' <<< "$manifest" > /dev/null \
    || die "unknown configuration: $configuration"
  manifest=$(jq --arg name "$configuration" '
    .configurations |= with_entries(select(.key == $name))
  ' <<< "$manifest")
fi

shields=$(jq '[
  .configurations | to_entries[] | .key as $configuration |
    .value.files | to_entries[] |
    {address: ($configuration + ":" + .key), configuration: $configuration,
      name: .key, file: .value}
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
        reduce .[] as $shield ({configurations: $configurations};
          .configurations[$shield.configuration].files[$shield.name] =
            {file: $shield.file, status: $shield.status}
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
      (.configurations | to_entries[] |
        "Configuration \(.key):",
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

# Encryption targets an identity's public key when the manifest pairs
# one, so a passphrase or a hardware key is not needed, and presents the
# identity file otherwise. Decryption presents every identity file on
# disk; one paired with a public key, such as a teammate's, may be absent.
identity_args=()
recipient_args=()
while IFS= read -r entry; do
  identity=$(resolve_identity "$(jq -r .identity <<< "$entry")") || exit
  pubkey=$(jq -r '.pubkey // empty' <<< "$entry")
  if [[ -n $pubkey ]]; then
    recipient_args+=(--recipient "$pubkey")
  else
    [[ -f $identity ]] || die "master identity does not exist: $identity"
    recipient_args+=(--identity "$identity")
  fi
  [[ ! -f $identity ]] || identity_args+=(--identity "$identity")
done < <(jq -c '.masterIdentities[]' <<< "$manifest")
[[ ${#recipient_args[@]} -gt 0 ]] || die "no master identity declared"

# The primary identity, relative to the caller, is tried first or alone.
primary_identity=${NIXOS_SHIELDS_PRIMARY_IDENTITY:-}
decryption_args=()
if [[ -n $primary_identity ]]; then
  [[ -f $primary_identity ]] || die "primary identity does not exist: $primary_identity"
  decryption_args+=(--identity "$primary_identity")
fi
if [[ ${NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY:-} == true ]]; then
  [[ -n $primary_identity ]] \
    || die "NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY requires NIXOS_SHIELDS_PRIMARY_IDENTITY"
else
  decryption_args+=("${identity_args[@]}")
fi

if [[ $command_name == rekey ]]; then
  if [[ -n $rekey_identity ]]; then
    # An explicit identity is relative to the caller, not the flake directory.
    [[ -f $rekey_identity ]] || die "decryption identity does not exist: $rekey_identity"
    decryption_args=(--identity "$rekey_identity")
  fi
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

decrypt_file() {
  [[ ${#decryption_args[@]} -gt 0 ]] || die "no master identity file exists to decrypt $1"
  rage --decrypt "${decryption_args[@]}" --output "$plaintext" "$1"
}

# Encrypt beside the destination, then atomically replace it. A failed
# encryption cannot truncate the original, and the EXIT trap removes partials.
encrypt_file() {
  local destination=$1
  mkdir -p -- "$(dirname "$destination")"
  ciphertext=$(mktemp "$(dirname "$destination")/.nixos-shields.XXXXXX")
  rage --encrypt "${recipient_args[@]}" --output "$ciphertext" "$plaintext"
  mv -f -- "$ciphertext" "$destination"
  ciphertext=
}

if [[ $command_name == rekey ]]; then
  for file in "${files[@]}"; do
    decrypt_file "$file"
    encrypt_file "$file"
    echo "Rekeyed: ${file#"$flake_dir/"}"
  done
  exit 0
fi

existing=false
if [[ -f $file ]]; then
  existing=true
  decrypt_file "$file"
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
