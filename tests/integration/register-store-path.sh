# Make an existing sandbox input known to the evaluation store without
# taking ownership of it. --load-db needs its actual NAR hash and size.
registerStorePath() {
  local store_uri=$1 path=$2 hash size
  hash="sha256:$(nix-hash --type sha256 --base32 "$path")"
  size=$(nix-store --store "$store_uri" --dump "$path" | wc -c)
  printf '%s\n%s\n%s\n\n0\n' "$path" "$hash" "$size" \
    | nix-store --store "$store_uri" --load-db
}
