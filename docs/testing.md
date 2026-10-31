# Testing

`nix flake check` runs every check below. [AGENTS.md](../AGENTS.md#required-checks) lists the commands and CI setup.

The tests follow the devnix-labs test layout: one directory under [`tests/`](../tests) for each test kind, each with an entry point, `default.nix`, that lists its tests by hand. A test file missing from its entry point's list does not run. [`dev/default.nix`](../dev/default.nix) runs the unit and integration suites through nix-unit's flake-parts module, [`tests/default.nix`](../tests/default.nix) names the build tests, and [`dev/checks.nix`](../dev/checks.nix) adds `lint` and a `package-<name>` check for each package. treefmt-nix's flake-parts module adds the `treefmt` check.

| Check                 | Covers                                                                                                                                          |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `nix-unit`            | The nix-unit suites: those under `tests/unit` evaluate the kit's code alone, and those under `tests/integration` evaluate it inside flake-parts |
| `build-cli`           | The packaged command-line tool against the example consumer                                                                                     |
| `build-decrypt-cache` | The decrypt script and its decrypt cache                                                                                                        |
| `build-wrapped-nix`   | The wrapped Nix inside the build sandbox                                                                                                        |
| `treefmt`             | Whether `nix fmt` would change a file or report a finding                                                                                       |
| `lint`                | statix                                                                                                                                          |
| `package-<name>`      | Whether each package of the `packages` output except `default` builds: `decrypt`, `extra-builtins`, `nix`, `nix-plugins`, and `nixos-shields`   |

## `nix-unit`

The check runs the [nix-unit](https://github.com/nix-community/nix-unit) suites without the plugin, through [nix-unit's flake-parts module](https://github.com/nix-community/nix-unit/blob/main/lib/modules/flake/system.nix). The module publishes the suites as the flake output `tests.systems.<system>`, the unit suites under `unit` and the integration suites under `integration`, and runs them in the build sandbox with every flake input passed as `--override-input`. Each suite receives the context that [`tests/test-context.nix`](../tests/test-context.nix) builds: the kit's code imported from source, helpers that evaluate its modules, and the fixtures in [`tests/fixtures`](../tests/fixtures). A unit suite takes the path of the source file it tests, relative to `lib/` for library code.

Run the suites directly, against the flake's locked inputs, from the development shell:

```sh
nix-unit --flake .#tests.systems.x86_64-linux                     # every suite
nix-unit --flake .#tests.systems.x86_64-linux.integration         # the integration suites
nix-unit --flake .#tests.systems.x86_64-linux.unit.nixos.module   # one suite
nix-unit --flake .#tests.systems.x86_64-linux.unit.nixos.module --attr testDefaults   # one test
```

Select a single test with `--attr` beside its suite: nix-unit treats an attribute selected through the flake reference as a suite, so a test's full path there does not work.

Add `--override-input nixpkgs <flake-ref>` to run the suites against another nixpkgs.

The suites expect a Nix without the builtin. nix-unit reads `NIX_CONFIG`, so a shell started by the wrapped Nix, such as through its `nix develop`, inherits the wrapper's plugin setting and fails `nixos.module.testValuesNeedBuiltin`.

The unit suites:

- `nixos.module` drives the option tree of [`nixos/module.nix`](../nixos/module.nix) through `evalModules`. It covers defaults, the attribute set form every master identity entry reads back as, including agenix-rekey's `age.rekey.masterIdentities` value and a newline-terminated public key read through it, a relative string failing, age, age plugin, `ssh-ed25519`, `ssh-rsa`, and newline-terminated public keys reading back as given in `extraEncryptionPubkeys` and as a paired `pubkey`, recipients files as paths and absolute strings reading back as given, an empty string, a relative string, and another prefix failing in both with the public-key message, wiring files from `dir`, a file given as an absolute string, a file name without the `.nix.age` suffix failing, `values` being read-only, and reading a value reaching `importShield`, which fails without the builtin.
- `packages.extra-builtins.compose` merges the kit's builtins, imported from source, with a consumer's extra builtins under nix-plugins' arguments and a fake `exec`. It covers the kit's builtins alone, entries merged beside `importShield` and receiving `exec`, and the failures, giving each entry's position, for an entry defining `importShield` and for two entries with one name defining one name.
- `packages.extra-builtins.extra-builtins` imports the builtin file from source with a fake `exec` that returns its argv instead of running it. It covers the argv for paths and absolute strings, and the failures for an empty identity list, an identity list that is not a list or holds a relative string, and a shield file that is a relative string, has another suffix, or does not exist.
- `import-shield` applies `lib/import-shield.nix` to that fake builtin. It covers the identity of every master identity entry form, including a `null` `pubkey`, reaching the builtin alone; the entry-form failures, giving the entry's position, for identities that are not a list, an entry of another type, an entry without `identity`, an entry with an unknown attribute, and a `pubkey` that breaks the public-key rule; and the failure naming `lib.mkNix` without `extraBuiltins`, without `importShield`, for a missing file, and for each of those bad identities.
- `mk-nix` checks `lib.mkNix`'s extra builtins against a real package set: a string that names no store path and an entry not in a list fail before the bundle is built.
- `mk-manifest` checks `lib.mkManifest` directly for plain flakes: relative locations, identities outside the flake root staying absolute while shield files outside it fail, a relative identity string failing, the `identity` and `pubkey` entries it combines from configurations without duplicates, a `null` public key for a YubiKey stub and a binary identity under `tests/fixtures` that no entry pairs with one, the failure for one identity paired with different public keys, extra encryption pubkeys combined from configurations without duplicates, where recipients files inside the root become relative and those outside stay absolute, configurations without the shields module, and the removed `masterIdentities` and `files` arguments failing.

The integration suites:

- `flake-module` evaluates the flake-parts option tree through `evalFlakeModule`. It covers the manifest it publishes, `shields.configurations` being its only option, its defaults, and selecting configurations from another output.
- `flake-outputs` checks that the flake itself (`self`) exposes the code the other suites import from source: the `lib` functions and the modules.

## `build-cli`

The check copies the [example consumer](../examples/consumer) into a writable directory and drives the packaged tool. It asserts every refusal of the tool by its message, and covers:

- the `--help` text, and the refusals that need no manifest: no command, an unknown command or option, an option without a value, `--json`, `--configuration`, or `--identity` on a command that does not take it, `edit` without an address or with two, `list`, `rekey`, or `clean` with one, and `--flake` naming a directory without `flake.nix`
- a hand-written manifest whose shield file is absolute or leads out of the checkout through a symlink
- refusals that leave every shield file untouched and never start the editor: `edit` without `EDITOR`, `edit` on a declared shield file that is a directory, `edit` with `TMPDIR` inside the checkout, `rekey` with a declared shield file missing, `rekey --identity` with an identity that does not exist, no master identity declared, a master identity without a paired public key that does not exist, and a recipients file that does not exist
- text and JSON listings without a flake-scoped group, configuration filtering, and local directory selection
- shield values reaching `alpha`'s ordinary options and a deploy-rs-shaped output, and `beta` failing with its missing shield file's location
- one shield file declared by both configurations, readable through each after `edit` and `rekey`
- unchanged and changed edits, creating a missing shield, editor failure and an editor removing the plaintext file, each leaving the shield file byte-identical, bare addresses failing as unknown, and temporary-file cleanup
- encryption to all master identities, including one that only `alpha` declares, and rotation to a second identity verified through the wrapped Nix
- a passphrase-protected identity paired with its public key in the manifest, which `edit` and `rekey` encrypt to without a prompt and whose key then opens every shield
- `rekey` decrypting with every master identity when the first cannot open the shields
- a primary identity relative to the caller decrypting alone in `edit`, `rekey --identity` decrypting with the given identity alone, and the primary identity variables in evaluation through the wrapped Nix
- `edit` reading a shield from the decrypt cache that an evaluation filled, with only an identity at hand that cannot open it
- a master identity outside the flake root, kept absolute in the manifest, working for `edit`, `rekey` from another directory, and evaluation through the wrapped Nix, beside a teammate's identity paired with its public key whose file does not exist
- public keys read at encryption time from FIDO2 stubs inside and outside the flake root whose comments hold X25519 keys, shown by those keys opening the shield while no age plugin is installed, with the manifest's `pubkey` left `null`; a declared `pubkey` winning over a stub's comment; FIDO2 stubs with no key or several keys presented as identities, which fails without the plugin; and a stand-in `age-plugin-yubikey` showing that rage receives a YubiKey stub's recipient, or the stub's identity line when it has no recipient
- a binary passphrase-protected identity inside the flake root without a `pubkey`, which leaves `list` and the manifest working and which `edit` presents through a scripted pinentry without noise about the binary file
- the unencrypted private key warning for the example's throwaway identity and an unencrypted OpenSSH key, with the command still succeeding, and none for an identity outside the flake root, a YubiKey stub, a passphrase-protected age identity, or a passphrase-protected OpenSSH key
- an extra encryption pubkey given as a public key by `alpha` and one given through a recipients file by `beta`, combined in the manifest, each opening the shield `edit` writes and every shield after `rekey`, while decryption in `edit`, `rekey`, and evaluation works without them
- no shield file and no outside identity copied into the store
- decrypt cache removal outside a flake, refusal of a decrypt cache containing the selected flake, and removal of the cache an evaluation filled

Every run of the tool that names no decrypt cache gets a cold one of its own, so a decryption the check asserts on is never served by an entry left behind earlier. Evaluation shares one decrypt cache.

## `build-decrypt-cache`

The check drives the decrypt script directly with a throwaway master identity and a counting wrapper in place of `rage`. It covers:

- a miss decrypting and a hit not, including for a copy of the same file elsewhere
- a changed file getting its own entry beside the old one
- `--print-out-path` naming the entry, and `NIXOS_SHIELDS_CACHE_DIR` moving the directory
- absent identity files skipped, and failing when none exists
- a primary identity followed by the given ones, and tried before them, shown by a stand-in `age-plugin-yubikey` that a YubiKey stub given first starts and that a primary identity able to decrypt leaves idle
- `_ONLY` decrypting with a primary identity relative to the caller alone, and the failures of `_ONLY` without a primary identity and of a missing primary identity
- a hit ignoring the primary identity variables
- a failed decryption leaving no partial file
- `--clean` removing the decrypt cache and accepting one already removed, and refusing a symlink and a directory containing the home directory, the current directory, or a directory given to it, each case tripping only its own refusal

The script's refusal of a decrypt cache owned by another user stays untested, because the build sandbox cannot create a directory that another user owns.

## `build-wrapped-nix`

The check verifies that the wrapped Nix's multi-call binaries keep their identity and load the builtin. It then evaluates `lib.importShield` on a fixture encrypted to an identity generated at check time, both with the kit's builtins alone and with a consumer's extra builtins supplied to `lib.mkNix`, a file and a directory of symlinks that imports a file inside it. It loads the consumer's builtins in pure evaluation too, which admits only files inside the extra-builtins directory. With the kit's builtins alone, it also calls the builtin directly with the identity and the shield file as absolute strings, which the unit suites' fake `exec` cannot show, and confirms that neither the fixture nor the identity is copied into the store. The builtin's checks and the identities `lib.importShield` hands it are in the `packages.extra-builtins.extra-builtins` and `import-shield` unit suites. It doubles as the ABI canary: it rebuilds whenever the Nix or the plugin changes.

## `treefmt` and `lint`

`treefmt` runs every program that `nix fmt` runs, as configured in `dev/treefmt.nix`, against a copy of the source: nixfmt, deadnix, prettier, shfmt, shellcheck, and actionlint. It fails when a program changes a file or reports a finding it cannot fix, and its build log shows the diff that `nix fmt` would make. `nix fmt` applies deadnix's and the formatters' changes; review the diff before committing. Shell scripts without a shebang start with `# shellcheck shell=bash`, since the program has no shell option.

`lint` runs `statix check` from the source root. statix runs outside treefmt, because treefmt-nix's statix program runs `statix fix`, which passes the lints that statix cannot fix.
