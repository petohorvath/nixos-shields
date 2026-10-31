# Changelog

## 0.2.0 - Unreleased

### Added

- `packages.default`, the `nixos-shields` command-line tool.
- The `treefmt-nix` input, which only the kit's development checks use. Drop it with `inputs.nixos-shields.inputs.treefmt-nix.follows = "";`.
- `flakeModules.default`, the flake-parts module.
- The `tests` output, the nix-unit suites, which serves development only, and the `nix-unit` input that runs them. The input's `nixpkgs` follows this flake's, so consumers lock no second nixpkgs; a consumer can drop the input with `inputs.nixos-shields.inputs.nix-unit.follows = "";`.
- `age.shields.masterIdentities` entries can pair an identity with its public key as `{ identity; pubkey; }`, the form of agenix-rekey's `age.rekey.masterIdentities`, so assigning that option's value works. `nixos-shields edit` and `rekey` encrypt to a paired public key instead of presenting the identity file, so a passphrase-protected identity or another person's YubiKey needs no prompt. A paired public key must start with `age1`, as age plugin keys do too, `ssh-ed25519 `, or `ssh-rsa `; any other `pubkey` fails evaluation, and with it the manifest. `lib.importShield` accepts the same entries.
- A master identity can lie outside the flake root, given as an absolute path string such as `"/home/alice/.config/age/shields.txt"`, so a plain age key or SSH key is never committed or copied into the Nix store. Plain keys belong there. The manifest keeps such an identity absolute, `nixos-shields` finds it from any working directory, and the `importShield` builtin accepts absolute path strings as well as paths. Shield files must still lie inside the flake root.
- When no configuration pairs a master identity with a public key, `nixos-shields edit` and `rekey` read one from its YubiKey or FIDO2 identity stub, inside or outside the flake root: the key in the stub's `Recipient:` or `public key:` comment, following agenix-rekey's rules of exactly one plugin identity line and exactly one key. They then encrypt to the key without touching the hardware. Any other file, including a stub with no key or several, is presented as an identity, and a declared `pubkey` wins over the stub's. The manifest reads no identity file, so its `pubkey` stays `null` for such an identity.
- `age.shields.extraEncryptionPubkeys` lists extra encryption pubkeys, such as an offline backup key, that every shield is encrypted to and that are never used to decrypt, as with agenix-rekey's `age.rekey.extraEncryptionPubkeys`. An entry is a recipients file given as a path or an absolute path string, inside or outside the flake root, or else a public key, which must start with `age1`, as age plugin keys do too, `ssh-ed25519 `, or `ssh-rsa `. Any other string, such as `""` or a relative path string, fails evaluation, and with it the manifest. The manifest gains an `extraEncryptionPubkeys` field that combines every configuration's entries without duplicates, each as `{ pubkey }` or `{ recipientsFile }`, and `nixos-shields edit` and `rekey` encrypt every shield to them as well as to the master identities.
- `NIXOS_SHIELDS_PRIMARY_IDENTITY` names an identity file tried before the master identities, and `NIXOS_SHIELDS_PRIMARY_IDENTITY_ONLY=true` restricts decryption to it, in the command-line tool and in evaluation through the wrapped Nix.
- `nixos-shields-decrypt --clean`, from `packages.<system>.decrypt`, removes the decrypt cache with the refusals of `nixos-shields clean`, which calls it, and accepts further directories to protect.
- Every `nixos-shields` command that reads the manifest warns on stderr about each master identity inside the flake root that holds an unencrypted private key, an `AGE-SECRET-KEY-` line or an OpenSSH private key whose cipher is `none`. The warning names the file, suggests a YubiKey or FIDO2 identity stub, a passphrase-protected identity, or a path outside the flake, and does not fail the command. The example consumer's throwaway identity triggers it.

### Changed

- Decryption, in `nixos-shields` and in evaluation through the wrapped Nix, skips master identity files that do not exist, so an identity paired with its public key, such as a teammate's, need not be on disk; a misspelled one is skipped the same way, without a message. Encryption still requires the file of an identity without a public key.
- `nixos-shields rekey` without `--identity` decrypts with every master identity in manifest order, as `edit` and evaluation do, instead of only the first.
- `nixos-shields edit` and `rekey` read shields through the decrypt cache, as evaluation does, so a shield that evaluation or an earlier command unlocked is not decrypted again and a hardware identity is not prompted again. Saving adds no entry, so the next evaluation still checks that the new shield file opens. `rekey --identity` decrypts only the shields without an entry with the given identity. Choosing identities and removing the decrypt cache move into the decrypt script, `packages.<system>.decrypt`.
- Every shield belongs to a configuration, and every configuration declares its own master identities, as with agenix-rekey. The manifest's `masterIdentities`, from `lib.mkManifest` and `flakeModules.default`, combines every configuration's `age.shields.masterIdentities`, each identity once, and `nixos-shields edit` and `rekey` encrypt every shield to all of them. Share master identities through a NixOS module imported by each configuration, share data by declaring one shield file in several configurations, and read a configuration's values from outside it through `nixosConfigurations.<name>.config.age.shields.values`.
- The option `age.shields.masterIdentities` reads back each entry as `{ identity; pubkey; }`, with `pubkey = null` for an entry given as a path.
- `packages.<system>.extra-builtins` is a directory, the kit's builtins as `lib.mkNix` loads them, instead of a file.
- Each entry of the manifest's `masterIdentities` is an object with `identity`, the location, and `pubkey`, a public key or `null`, instead of a location string. Two configurations pairing one identity with different public keys fail evaluation.
- The `importShield` builtin owns every check on its arguments and rejects an empty identity list itself; its messages start with `nixos-shields:` instead of `importShield:`. Without the builtin, `lib.importShield` fails only with the message naming `lib.mkNix`, even for a missing shield file.
- `nixos-shields list` headings name each configuration as `Configuration <name>:`.
- Unit tests run under nix-unit and can be run directly from the development shell.
- Formatting and lint are the flake checks `treefmt` and `lint`, run by `nix flake check` and CI. `nix fmt` runs treefmt-nix with nixfmt, deadnix, prettier, shfmt, shellcheck, and actionlint instead of nixfmt-tree.
- The tests follow the devnix-labs test layout. The nix-unit suites import the kit from source and run as the `nix-unit` check, through nix-unit's flake-parts module, instead of the `tests` check; a new `flake-outputs` suite checks that the flake exposes the same code. The `cli`, `decrypt-cache`, and `integration` checks are renamed `build-cli`, `build-decrypt-cache`, and `build-wrapped-nix`, and a `package-<name>` check builds each package. Run the suites directly with `nix-unit --flake .#tests.systems.<system>`.
- The `nixpkgs` input tracks `nixos-26.05` instead of `nixos-unstable`, locked to the nixos-project-policy v0.6 stable pin; consumers that do not make it follow their own nixpkgs get the stable release.
- CI calls the shared project policy `v0.6` workflow instead of its own. It runs on x86_64-linux and aarch64-linux and tests the locked nixpkgs and the policy's stable and unstable pins; the required statuses become `Policy / Check (<system>)` and `Policy / Tests (locked|stable|unstable, <system>)`. There are no VM tests, so no `Policy / VM tests (locked|stable|unstable, <system>)` status is required.

### Removed

- The aarch64-darwin outputs. The kit supports only x86_64-linux and aarch64-linux, the systems CI tests.
- The `flakeModule` output; import `flakeModules.default` instead.
- The `git-hooks` input; drop any follows or overrides of `nixos-shields/git-hooks`.
- The development-shell Git hooks.
- Flake-scoped shields. `flakeModules.default` loses the `shields.dir`, `shields.masterIdentities`, `shields.files`, `shields.values`, and `shields.nixosModule` options; import `nixosModules.default` in each configuration instead, and keep `shields.configurations`.
- The `masterIdentities` and `files` arguments of `lib.mkManifest`, which now takes only `self` and `configurations`.
- `lib.mkExtraBuiltinsFile` and the `extraBuiltinsFile` argument of `lib.mkNix`, whose combined file failed in pure evaluation; pass a consumer's builtins as `extraBuiltins` instead. The wrapped Nix's `passthru.extraBuiltinsFile` becomes `passthru.extraBuiltinsDir`.
- The manifest's top-level `files` field.
- Bare `<name>` addresses in `nixos-shields`; address every shield as `<configuration>:<name>`.
- The flake-scoped group of `nixos-shields list`, in its text output and the `files` field of its JSON output.

### Fixed

- A consumer's own extra builtins load in pure evaluation, the mode of flake commands such as `nixos-rebuild --flake`. The documented combined file imported the kit's builtins from another store path, which nix-plugins admits only with `--impure`. `lib.mkNix` now takes the consumer's builtins as `extraBuiltins`, a list of files or directories, and copies them beside the kit's into one directory that it loads. An entry that defines `importShield`, or two entries that define one name, fail evaluation with a message giving the entry's position and name.
- The nix-plugins build no longer fails with nixpkgs that patches nix-plugins for Nix 2.33 and 2.34 itself, such as `nixos-unstable` from 2026-10-27: the kit's compatibility patch replaces nixpkgs' patches instead of being applied on top of them.
- A shield file given as an absolute path string decrypts. Before, it passed `nixos-shields list` and `edit`, then failed evaluation with `shield file must be an existing path` for a file that exists.
- A shield file whose name does not end in `.nix.age` fails the `age.shields.files` option, so `nixos-shields list` and `edit` refuse it too, instead of only evaluation failing.
- A failed decryption no longer leaves a partial file, which may hold plaintext, in the decrypt cache.

## 0.1.0 - 2026-09-14

### Added

- Evaluation-time imports of age-encrypted Nix expressions through `lib.importShield`, with a content-addressed, per-user decrypt cache and `NIXOS_SHIELDS_CACHE_DIR` override.
- Wrapped Nix 2.34 binary set from `lib.mkNix` and the `nix` package, a matching nix-plugins build with an in-kit compatibility patch, and composable extra builtins.
- NixOS module for configuration-scoped shields, flake-parts module for flake-scoped shields and shared defaults, and `lib.mkManifest` for plain flakes.
- `nixos-shields list`, `edit`, `rekey`, and `clean`, with manifest addresses, JSON listings, encryption to every master identity, and unchanged-edit preservation.
- Example consumer with a committed throwaway master identity, both shield scopes, and a deliberately missing shield file.
- Unit and sandbox integration checks, CI for formatting and x86_64-linux checks, and development-shell hooks that format on commit and run checks on push.
- Adoption recipes, shield-versus-secret guidance, glossary, and the evaluation-time decryption ADR.

Outputs are declared for x86_64-linux, aarch64-linux, and aarch64-darwin; x86_64-linux is tested. Shield values are readable in the Nix store and decrypt cache and must not contain runtime credentials.
