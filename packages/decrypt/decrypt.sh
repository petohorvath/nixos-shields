# shellcheck shell=bash
# nixos-shields-decrypt [--print-out-path] <shield-file> <identity>...
# nixos-shields-decrypt --clean [<protected-directory>...]
#
# Decrypts a shield file into the decrypt cache and prints the plaintext
# (or, with --print-out-path, the cache location). The cache entry is
# keyed by the file's content hash and base name, so an unchanged file
# never invokes the decryptor again, wherever the file lives. Evaluation
# and the command-line tool both read shields through it.
#
# NIXOS_SHIELDS_PRIMARY_IDENTITY names an identity file tried before the
# given ones; with NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY=true, it is the only
# one. Neither changes the cache key.
#
# --clean removes the decrypt cache, refusing a directory that contains
# /, the home directory, the current directory, or a directory given.

die() {
  echo "nixos-shields-decrypt: $*" >&2
  exit 1
}

cache_dir="${NIXOS_SHIELDS_CACHE_DIR:-/var/tmp/nixos-shields-$UID}"

if [[ ${1:-} == "--clean" ]]; then
  shift
  [[ ! -L $cache_dir ]] || die "refusing to remove a decrypt cache symlink: $cache_dir"
  if [[ ! -e $cache_dir ]]; then
    echo "Decrypt cache already empty: $cache_dir"
    exit 0
  fi
  [[ -d $cache_dir && -O $cache_dir ]] ||
    die "refusing to remove a decrypt cache that is not a directory owned by the current user: $cache_dir"
  cache_dir=$(realpath -e -- "$cache_dir")
  case $cache_dir in
  /nix/store | /nix/store/*) die "refusing to remove a decrypt cache in /nix/store" ;;
  esac
  # An accidental override such as /, ~ or . must not erase unrelated files.
  for protected in / "${HOME:-}" "$(pwd -P)" "$@"; do
    [[ -n $protected ]] || continue
    protected=$(realpath -m -- "$protected")
    [[ $protected != "$cache_dir" && $protected != "$cache_dir/"* ]] ||
      die "refusing to remove a decrypt cache containing $protected: $cache_dir"
  done
  rm -rf -- "$cache_dir"
  echo "Removed decrypt cache: $cache_dir"
  exit 0
fi

print_out_path=false
if [[ ${1:-} == "--print-out-path" ]]; then
  print_out_path=true
  shift
fi

file=$1
shift
identities=("$@")

hash=$(sha256sum "$file")
out="$cache_dir/${hash:0:32}-$(basename "$file" .age)"

umask 077
mkdir -p "$cache_dir"
# /var/tmp is world-writable: refuse a directory someone else planted.
[[ -O $cache_dir ]] || die "$cache_dir is not owned by the current user"

if [[ ! -e $out ]]; then
  primary=${NIXOS_SHIELDS_PRIMARY_IDENTITY:-}
  args=()
  if [[ -n $primary ]]; then
    [[ -f $primary ]] || die "primary identity does not exist: $primary"
    args+=(--identity "$primary")
  fi
  if [[ ${NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY:-} == true ]]; then
    [[ -n $primary ]] ||
      die "NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY requires NIXOS_SHIELDS_PRIMARY_IDENTITY"
  else
    # An identity paired with a public key, such as a teammate's key
    # outside the flake root, may be absent from this machine.
    for identity in "${identities[@]}"; do
      [[ ! -f $identity ]] || args+=(--identity "$identity")
    done
  fi
  [[ ${#args[@]} -gt 0 ]] || die "no master identity file exists to decrypt $file"
  # Decrypt beside the entry and move it in place so an interrupted
  # decryption never leaves a truncated plaintext that reads as a hit. The
  # EXIT trap removes the partial file of a failed one, which may hold
  # plaintext.
  partial=
  trap 'if [[ -n $partial ]]; then rm -f -- "$partial"; fi' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  partial=$(mktemp "$cache_dir/.partial.XXXXXX")
  rage --decrypt "${args[@]}" --output "$partial" "$file"
  mv "$partial" "$out"
  partial=
fi

if [[ $print_out_path == true ]]; then
  echo "$out"
else
  cat "$out"
fi
