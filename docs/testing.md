# Testing

`nix flake check` runs every check below. [AGENTS.md](../AGENTS.md#required-checks) lists the commands and CI setup.

| Check | Covers |
| --- | --- |
| `integration` | The wrapped Nix inside the build sandbox |
| `cli` | The packaged command-line tool against the example consumer |
| `tests` | The nix-unit suites under `tests/suites` |
| `decrypt-cache` | The decrypt script and its decrypt cache |
| `formatting` | Whether the formatter would change a file |
| `lint` | statix, deadnix, shellcheck, and actionlint |

## `integration`

The check verifies that the wrapped Nix's multi-call binaries keep their identity and load the builtin. It then evaluates `lib.importShield` on a fixture encrypted to an identity generated at check time, both with the default extra-builtins file and through a consumer's combined file supplied to `lib.mkNix`. It doubles as the ABI canary: it rebuilds whenever the Nix or the plugin changes.

## `cli`

The check copies the [example consumer](../examples/consumer) into a writable directory and drives the packaged tool. It covers:

- text and JSON listings, configuration filtering, and local directory selection
- shield values reaching `alpha`'s ordinary options, and `beta` failing with its missing shield file's location
- unchanged and changed edits, creating a missing shield, editor failure, and temporary-file cleanup
- encryption to all master identities, and rotation to a second identity verified through the wrapped Nix
- no shield file copied into the store
- decrypt cache removal

## `tests`

The check runs the [nix-unit](https://github.com/nix-community/nix-unit) suites without the plugin, against the flake's public outputs:

- `nixosModule` drives the option tree through `evalModules`. It covers defaults, wiring files from `dir`, `values` being read-only, and the failures a missing file or an empty identity list produce.
- `flakeModule` evaluates the flake-parts option tree and the pre-configured NixOS module. It covers relative manifest locations, the flake options' defaults, `values` being read-only, the module's inherited and overridden defaults, selecting configurations from another output, and importing the pre-configured module beside `nixosModules.default`. It also checks `lib.mkManifest` directly for plain flakes.

## `decrypt-cache`

The check drives the decrypt script directly with a throwaway master identity and a counting wrapper in place of `rage`. It asserts that a miss decrypts, that a hit does not, including for a copy of the same file elsewhere, that a changed file gets its own entry, that `--print-out-path` names the entry, and that `NIXOS_SHIELDS_CACHE_DIR` moves the directory.

## `formatting` and `lint`

Both checks run against a copy of the source. `formatting` fails when `nix fmt` would change a file.
