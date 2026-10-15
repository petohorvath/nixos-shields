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

The tool runs against the flake in the current directory, or against `--flake <directory>`, given before or after the command. The directory must be a local checkout containing `flake.nix`; flake references such as `github:owner/repo` or `path:...`, and directories inside `/nix/store`, are refused. The tool evaluates the flake's `shields` [manifest](reference.md#manifest) once per command and resolves its relative file locations against the checkout. A master identity outside the flake root has an absolute location in the manifest and is used where it lies.

Encryption presents an identity file only when the manifest pairs no public key with it, and fails when that file does not exist. Decryption tries every identity file that exists, so an identity paired with a public key, such as a teammate's, need not be on disk.

## Addresses

An address is `<configuration>:<name>`, such as `alpha:facts`. A bare name is an unknown address. Names and file locations come from the manifest, so declare a shield in a configuration before editing it. A shield file that several configurations declare has an address in each, such as `alpha:shared` and `beta:shared`, and editing it through any of them changes it for all.

## `list`

```sh
nixos-shields list
nixos-shields list --json
nixos-shields list --configuration alpha
nixos-shields --flake ../fleet list --configuration alpha --json
```

`list` groups shields by configuration and shows each address, file location, `exists` or `missing` status, and totals. `--configuration <name>` includes only that configuration's shields and fails for an unknown configuration. Listing does not decrypt shields, so it reports missing files too. Totals count addresses, so a shield file that two configurations declare counts twice.

`--json` prints a `configurations` group that matches the manifest, with each file as `{"file":"shields/alpha.nix.age","status":"exists"}`, and a `totals` object with `total`, `exists`, and `missing` counts.

## `edit`

```sh
EDITOR=vim nixos-shields edit beta:shared
EDITOR='code --wait' nixos-shields edit alpha:facts
```

`edit` decrypts the shield into a private temporary directory outside the checkout, runs `$EDITOR` as a Bash command with the plaintext file appended, and removes the directory on exit. Set `EDITOR` to a command that waits until editing finishes. The temporary directory follows `TMPDIR`; the tool refuses one inside the checkout.

- An unchanged edit leaves the shield file byte-identical.
- An existing shield is decrypted with every master identity in the manifest, in order, after any [primary identity](#primary-identity).
- A changed edit encrypts to the master identities of every configuration, as the manifest combines them, and replaces the shield file only after encryption succeeds. It encrypts to an identity's public key when the manifest pairs one, and presents the identity file otherwise.
- A declared file that does not exist starts from `{}` and is created even when the editor leaves that expression unchanged.
- A failed editor, or one that removes the plaintext file, leaves the shield file untouched.

## `rekey`

```sh
nixos-shields rekey
nixos-shields rekey --identity /path/to/previous-identity.txt
```

`rekey` decrypts every declared shield and encrypts it to every current master identity, as `edit` does: to its public key when the manifest pairs one, and to the identity file otherwise. Without `--identity`, it decrypts with every master identity in the manifest, in order, after any [primary identity](#primary-identity), so it works when the first declared identity is not at hand. With `--identity`, a file relative to the current directory or an absolute path, it decrypts with that identity alone and ignores the primary identity. Every declared shield file must exist.

To rotate master identities:

1. Change the master identity list of every configuration to the new identities.
2. Run `nixos-shields rekey --identity <old-identity>` with an old identity that is still available.

An old identity loses access to the current shield files only once it leaves every declared list. It can still decrypt earlier versions in git history.

## Primary identity

`NIXOS_SHIELDS_PRIMARY_IDENTITY` names an identity file to try before the declared master identities, so a user holding one of several YubiKeys is not prompted for the others. The file is relative to the current directory, or an absolute path, and need not be declared. With `NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY=true`, it is the only identity tried; setting `_ONLY` without a primary identity fails.

```sh
NIXOS_SHIELDS_PRIMARY_IDENTITY=master-identities/yubikey-2.txt \
NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY=true \
  nixos-shields edit alpha:facts
```

The variables affect decryption in `edit` and in `rekey` without `--identity`, never encryption. Evaluation through the wrapped Nix honours them too, as the [reference](reference.md#primary-identity) describes.

## `clean`

```sh
nixos-shields clean
```

`clean` removes the current user's [decrypt cache](reference.md#decrypt-cache), honouring `NIXOS_SHIELDS_CACHE_DIR`. It works outside a flake and does not evaluate a manifest. It refuses a decrypt cache directory that is a symlink, is not owned by the current user, lies in `/nix/store`, or contains `/`, the home directory, the current directory, or the selected flake.
