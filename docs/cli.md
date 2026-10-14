# Command-line tool

`nixos-shields` lists, edits, and rekeys the shields a consumer flake declares, and removes the decrypt cache. It is the flake's default package:

```sh
nix shell github:petohorvath/nixos-shields
```

```console
$ nixos-shields --help
Usage: nixos-shields [--flake <directory>] <command>
  list [--json] [--configuration <name>]
  edit <address>                         Edit with $EDITOR
  rekey [--identity <file>]               Encrypt to all master identities
  clean                                 Remove the user's decrypt cache
```

## Flake selection

The tool runs against the flake in the current directory, or against `--flake <directory>`, given before or after the command. The directory must be a local checkout containing `flake.nix`; flake references such as `github:owner/repo` or `path:...`, and directories inside `/nix/store`, are refused. The tool evaluates the flake's `shields` [manifest](reference.md#manifest) once per command and resolves its file locations against the checkout.

## Addresses

An address is a bare name for a flake-scoped shield, such as `shared`, or `<configuration>:<name>` for a configuration-scoped shield, such as `alpha:facts`. Names and file locations come from the manifest, so declare a shield in the flake before editing it.

## `list`

```sh
nixos-shields list
nixos-shields list --json
nixos-shields list --configuration alpha
nixos-shields --flake ../fleet list --configuration alpha --json
```

`list` groups shields by scope and shows each address, file location, `exists` or `missing` status, and totals. `--configuration <name>` includes only that configuration's shields and fails for an unknown configuration. Listing does not decrypt shields, so it reports missing files too.

`--json` prints `files` and `configurations` groups that match the manifest, with each file as `{"file":"shields/alpha.nix.age","status":"exists"}`, and a `totals` object with `total`, `exists`, and `missing` counts.

## `edit`

```sh
EDITOR=vim nixos-shields edit shared
EDITOR='code --wait' nixos-shields edit alpha:facts
```

`edit` decrypts the shield into a private temporary directory outside the checkout, runs `$EDITOR` as a Bash command with the plaintext file appended, and removes the directory on exit. Set `EDITOR` to a command that waits until editing finishes. The temporary directory follows `TMPDIR`; the tool refuses one inside the checkout.

- An unchanged edit leaves the shield file byte-identical.
- A changed edit encrypts to every master identity in the manifest, the flake-wide ones and those of every configuration, and replaces the shield file only after encryption succeeds.
- A declared file that does not exist starts from `{}` and is created even when the editor leaves that expression unchanged.
- A failed editor, or one that removes the plaintext file, leaves the shield file untouched.

## `rekey`

```sh
nixos-shields rekey
nixos-shields rekey --identity /path/to/previous-identity.txt
```

`rekey` decrypts every declared shield with `--identity` and encrypts it to every current master identity. `--identity` is a file relative to the current directory, or an absolute path, and defaults to the first master identity in the manifest. Every declared shield file must exist.

To rotate master identities:

1. Change the declared master identity lists, flake-wide and in every configuration, to the new identities.
2. Run `nixos-shields rekey --identity <old-identity>` with an old identity that is still available.

An old identity loses access to the current shield files only once it leaves every declared list. It can still decrypt earlier versions in git history.

## `clean`

```sh
nixos-shields clean
```

`clean` removes the current user's [decrypt cache](reference.md#decrypt-cache), honouring `NIXOS_SHIELDS_CACHE_DIR`. It works outside a flake and does not evaluate a manifest. It refuses a decrypt cache directory that is a symlink, is not owned by the current user, lies in `/nix/store`, or contains `/`, the home directory, the current directory, or the selected flake.
