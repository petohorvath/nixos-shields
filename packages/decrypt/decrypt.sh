# nixos-shields-decrypt [--print-out-path] <shield-file> <identity>...
#
# Decrypts a shield file into the decrypt cache and prints the plaintext
# (or, with --print-out-path, the cache location). The cache entry is
# keyed by the file's content hash and base name, so an unchanged file
# never invokes the decryptor again, wherever the file lives.
#
# NIXOS_SHIELDS_PRIMARY_IDENTITY names an identity file tried before the
# given ones; with NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY=true, it is the only
# one. Neither changes the cache key.

print_out_path=false
if [[ ${1:-} == "--print-out-path" ]]; then
  print_out_path=true
  shift
fi

file=$1
shift
identities=("$@")

cache_dir="${NIXOS_SHIELDS_CACHE_DIR:-/var/tmp/nixos-shields-$UID}"
hash=$(sha256sum "$file")
out="$cache_dir/${hash:0:32}-$(basename "$file" .age)"

umask 077
mkdir -p "$cache_dir"
# /var/tmp is world-writable: refuse a directory someone else planted.
[[ -O $cache_dir ]] || {
  echo "nixos-shields-decrypt: $cache_dir is not owned by the current user" >&2
  exit 1
}

if [[ ! -e $out ]]; then
  primary=${NIXOS_SHIELDS_PRIMARY_IDENTITY:-}
  args=()
  if [[ -n $primary ]]; then
    [[ -f $primary ]] || {
      echo "nixos-shields-decrypt: primary identity does not exist: $primary" >&2
      exit 1
    }
    args+=(--identity "$primary")
  fi
  if [[ ${NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY:-} == true ]]; then
    [[ -n $primary ]] || {
      echo "nixos-shields-decrypt: NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY requires NIXOS_SHIELDS_PRIMARY_IDENTITY" >&2
      exit 1
    }
  else
    for identity in "${identities[@]}"; do
      args+=(--identity "$identity")
    done
  fi
  # Decrypt beside the entry and move it in place so an interrupted
  # decryption never leaves a truncated plaintext that reads as a hit.
  partial=$(mktemp "$cache_dir/.partial.XXXXXX")
  rage --decrypt "${args[@]}" --output "$partial" "$file"
  mv "$partial" "$out"
fi

if [[ $print_out_path == true ]]; then
  echo "$out"
else
  cat "$out"
fi
