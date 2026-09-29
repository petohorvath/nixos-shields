# nixos-shields

Evaluation-time encrypted Nix expressions. A shield keeps identifying configuration values (domain names, real usernames, MAC addresses, disk serials) out of a public git repository while Nix can still read them during evaluation.

## Security boundary

A shield is not a secret. Its decrypted values land in the Nix store of every machine that evaluates or deploys the configuration, and in the per-user decrypt cache on disk. Anything that must stay confidential after deployment (passwords, tokens, private keys) belongs in a runtime secret manager such as agenix or sops-nix, never in a shield.

## Shields

A shield is a Nix expression stored age-encrypted in git and decrypted when Nix evaluates it. Its file name ends in `.nix.age`. It is encrypted to every master identity of the repository (a YubiKey plugin identity, an SSH key, or a plain age key), so any one of them can open it. [CONTEXT.md](CONTEXT.md) holds the full glossary; [ADR 0001](docs/adr/0001-eval-time-decryption-via-exec-builtin.md) records why decryption happens at evaluation time.

## Supported Nix version and plugin ABI

The shield builtin is provided by [nix-plugins](https://github.com/shlevy/nix-plugins), which must be compiled against the exact Nix that loads it. The kit builds it against the Nix 2.34 series from nixpkgs (`nixVersions.nix_2_34`). This ABI requirement is why the kit supplies a wrapped Nix together with the matching plugin, rather than loading the plugin into an arbitrary system Nix. A [compatibility patch](packages/nix-plugins/nix-2.34.patch) is carried in-kit until an upstream nix-plugins release builds against that Nix. A newer Nix or a newer nix-plugins may make the patch unnecessary, or need new hunks.

Only x86_64-linux is exercised by the checks; outputs are declared for aarch64-linux and aarch64-darwin as well. x86_64-darwin is not declared, as nixpkgs dropped it in 26.11.

## Wrapped Nix

`lib.mkNix` returns a Nix binary set whose every invocation loads the builtin. Each binary is wrapped individually with `NIX_CONFIG` set for that process only and argv[0] preserved, so `nix-store`, `nix-build` and friends keep their multi-call behaviour and nothing is exported into the caller's shell.

```nix
nixos-shields.lib.mkNix {
  inherit pkgs;
  nix = pkgs.nixVersions.nix_2_34; # default; a concrete series, never pkgs.nix
  extraConfig = "accept-flake-config = true"; # the kit sets no such policy itself
  extraBuiltinsFile = nixos-shields.lib.mkExtraBuiltinsFile { inherit pkgs; }; # default
}
```

A ready-made set with defaults:

```sh
nix shell github:petohorvath/nixos-shields#nix
```

### Tools that invoke Nix

`nixos-rebuild`, `nixos-anywhere`, and `disko` include their own Nix in their executable search paths. Override their `nix` argument so evaluations they launch also load the shield builtin. In a consumer's development shell, with `nixos-shields` bound to the flake input and `pkgs` to a Linux package set:

```nix
let
  nix = nixos-shields.lib.mkNix {
    inherit pkgs;
    extraConfig = "accept-flake-config = true"; # optional consumer policy
  };
in
pkgs.mkShellNoCC {
  packages = [
    nix
    nixos-shields.packages.${pkgs.stdenv.hostPlatform.system}.nixos-shields
    (pkgs.nixos-rebuild.override { inherit nix; })
    (pkgs.nixos-anywhere.override { inherit nix; })
    (pkgs.disko.override { inherit nix; })
  ];
}
```

Keep these overrides in the consumer; they are not kit outputs. The recipe uses the packages from nixpkgs; packages supplied by a tool's own flake may expose different override arguments.

### Composing extra builtins

Nix has one `extra-builtins-file` setting. Build the kit's file, import it with the arguments supplied by nix-plugins, and merge your own builtins into the returned attribute set. Hand that combined file to `lib.mkNix`:

```nix
let
  kitBuiltins = nixos-shields.lib.mkExtraBuiltinsFile { inherit pkgs; };
  combinedBuiltins = pkgs.writeText "extra-builtins.nix" ''
    args:
    (import ${kitBuiltins} args) // {
      consumerAnswer = 42;
    }
  '';
in
nixos-shields.lib.mkNix {
  inherit pkgs;
  extraBuiltinsFile = combinedBuiltins;
}
```

This exposes both `builtins.extraBuiltins.importShield` and `builtins.extraBuiltins.consumerAnswer`. Use distinct names for your additions so they do not replace the kit's builtin.

## Importing a shield

`lib.importShield` takes the master identity list and the shield file and returns the decrypted value. It fails with a message naming the file when the file does not exist, and with an explicit message when the identity list is empty.

```nix
nixos-shields.lib.importShield [ ./master-identities/yubikey-1.txt ] ./shields/beta.nix.age
```

## NixOS module

`nixosModules.default` exposes a configuration's shields under `age.shields`. The module knows nothing about configuration names or directory layout: the consumer's own wiring decides which file each configuration reads.

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `age.shields.masterIdentities` | list of paths | `[ ]` | Age identity files, any one of which can decrypt every shield of the configuration. Evaluating a shield with none set fails. |
| `age.shields.dir` | path | none | The directory holding the shield files. Never read by the kit; it exists so the wiring below can build file locations from it. |
| `age.shields.files` | attribute set of paths | `{ }` | Shield files by name. A file that does not exist fails evaluation with a message naming it. |
| `age.shields.values` | attribute set, read-only | derived | The decrypted value of each file in `files`, by name. Each value is decrypted only when something reads it. |

For a plain flake, the following `flake.nix` wires the module and publishes the manifest used by the command-line tool. It reads `shields/alpha.nix.age`; use your own master identity and shield file locations, all under the flake root:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.nixos-shields.url = "github:petohorvath/nixos-shields";
  inputs.nixos-shields.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, nixos-shields, ... }:
  let
    masterIdentities = [ ./master-identities/yubikey-1.txt ];
  in {
    shields = nixos-shields.lib.mkManifest {
      inherit self masterIdentities;
      configurations = self.nixosConfigurations;
    };

    nixosConfigurations.alpha = nixpkgs.lib.nixosSystem {
      modules = [
        nixos-shields.nixosModules.default
        ({ config, ... }: {
          age.shields = {
            inherit masterIdentities;
            dir = ./shields;
            files.facts = config.age.shields.dir + "/alpha.nix.age";
          };
          networking.domain = config.age.shields.values.facts.domain;
          nixpkgs.hostPlatform = "x86_64-linux";
          system.stateVersion = "26.05";
        })
      ];
    };
  };
}
```

Reading a value needs the wrapped Nix, so the builtin is loaded; without it evaluation fails naming `lib.mkNix`.

## flake-parts module

Import `nixos-shields.flakeModules.default` in a flake-parts flake to declare flake-scoped shields and share defaults with configurations. The module uses the libraries supplied by the consumer's flake-parts; it introduces no additional flake input.

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `shields.dir` | path | none | Shield directory, passed to the pre-configured NixOS module. |
| `shields.masterIdentities` | list of paths | `[ ]` | Identities used for flake-scoped shields and as configuration defaults. |
| `shields.files` | attribute set of paths | `{ }` | Flake-scoped shield files by name. |
| `shields.values` | attribute set, read-only | derived | Decrypted flake-scoped values, read lazily before any configuration evaluates. |
| `shields.configurations` | attribute set of evaluated configurations | `config.flake.nixosConfigurations` | Configurations whose shield files enter the manifest. Override when your configurations live elsewhere. |
| `shields.nixosModule` | module, read-only | derived | The default NixOS module with directory and identities applied using `mkDefault`. Ordinary configuration assignments override them. |

For a flake-parts consumer, this `flake.nix` declares both scopes. Supply your own master identity and shield files, then add your configuration's remaining NixOS settings:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    nixos-shields.url = "github:petohorvath/nixos-shields";
    nixos-shields.inputs.nixpkgs.follows = "nixpkgs";
    nixos-shields.inputs.flake-parts.follows = "flake-parts";
  };

  outputs = inputs@{ flake-parts, nixpkgs, nixos-shields, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } ({ config, ... }: {
      imports = [ nixos-shields.flakeModules.default ];
      systems = [ "x86_64-linux" ];
      shields = {
        dir = ./shields;
        masterIdentities = [ ./master-identities/yubikey-1.txt ];
        files.shared = ./shields/shared.nix.age;
      };

      flake.sharedShield = config.shields.values.shared;
      flake.nixosConfigurations.alpha = nixpkgs.lib.nixosSystem {
        modules = [
          config.shields.nixosModule
          ({ config, ... }: {
            age.shields.files.facts = config.age.shields.dir + "/alpha.nix.age";
            networking.domain = config.age.shields.values.facts.domain;
            nixpkgs.hostPlatform = "x86_64-linux";
            system.stateVersion = "26.05";
          })
        ];
      };
    });
}
```

`shields.values.shared` is available before any configuration evaluates. Capture it in the outer flake-parts module or pass it through `specialArgs` when a NixOS module needs shared values; its `config` argument refers to the NixOS configuration. If you already use agenix-rekey, assign `shields.masterIdentities` from your existing master identity list in this outer module.

## Manifest

The flake-parts module publishes `shields` as a flake output. It lists declarations without decrypting values or requiring the shield files to exist. Every location is a string relative to the consumer's flake root; paths outside that root fail with a message naming the path. Configurations without the shields module appear with empty `files`.

For the example consumer, `nix eval --json .#shields` returns:

```json
{
  "masterIdentities": ["master-identities/throwaway.txt"],
  "files": {"shared": "shields/shared.nix.age"},
  "configurations": {
    "alpha": {"files": {"facts": "shields/alpha.nix.age"}},
    "beta": {"files": {"facts": "shields/beta.nix.age"}}
  }
}
```

Plain flakes can publish exactly the same manifest using `lib.mkManifest`, with no flake-parts dependency:

```nix
shields = nixos-shields.lib.mkManifest {
  inherit self;
  masterIdentities = [ ./master-identities/yubikey-1.txt ];
  files.shared = ./shields/shared.nix.age;
  configurations = self.nixosConfigurations;
};
```

Only `self` is required; `masterIdentities` defaults to `[ ]`, and `files` and `configurations` to `{ }`. Configuration-scoped files are taken from each configuration's `config.age.shields.files`.

## Command-line tool

The `nixos-shields` package is the flake's default package on each declared system:

```sh
nix shell github:petohorvath/nixos-shields
```

Run it in a consumer flake directory, or pass `--flake <directory>` before or after the command. The directory must be a local checkout containing `flake.nix`; flake references such as `github:owner/repo`, `path:...`, and directories inside `/nix/store` are refused. The tool evaluates the `shields` manifest once per command and resolves its file locations against that checkout.

An **address** is a bare name for a flake-scoped shield (`shared`), or `<configuration>:<name>` for a configuration-scoped shield (`alpha:facts`). Names and file locations come from the manifest; declare a new address in the flake before editing it.

```sh
nixos-shields list
nixos-shields list --json
nixos-shields --flake ../fleet list --configuration alpha
nixos-shields list --configuration alpha --json
EDITOR=vim nixos-shields edit shared
EDITOR='code --wait' nixos-shields edit alpha:facts
nixos-shields rekey
nixos-shields rekey --identity /path/to/previous-identity.txt
nixos-shields clean
```

`list` groups shields by scope, showing each address, file location, `exists` or `missing` status, and totals. `--configuration` includes only that configuration's shields. JSON has `files` and `configurations` groups matching the manifest; each file becomes `{"file":"shields/alpha.nix.age","status":"exists"}`. Its `totals` object contains `total`, `exists`, and `missing` counts. Listing does not decrypt shields, so a missing file can still be listed.

`edit` decrypts into a private temporary directory outside the checkout, runs `$EDITOR` as a Bash command with the plaintext file appended, then removes the directory on exit. Set the editor to wait until editing finishes. An unchanged edit leaves the shield file byte-identical. A changed edit encrypts to every master identity in the manifest and replaces the shield file only after encryption succeeds. A declared file that does not exist starts from `{}` and is created even when the editor leaves that empty expression unchanged. A failed editor leaves the shield file untouched.

`rekey` decrypts every shield using `--identity` (a file relative to your current directory or an absolute path), defaulting to the first master identity in the manifest, and encrypts to every current master identity. To rotate identities, change the declared list to the new identities, keep an old identity available, and pass it with `--identity`. All declared shield files must exist. The old identity loses access only when it is no longer in the declared list; it can still decrypt earlier versions in git history.

`clean` removes the current user's decrypt cache, honouring `NIXOS_SHIELDS_CACHE_DIR`. It works outside a flake and does not evaluate a manifest.

## Example consumer

[examples/consumer](examples/consumer) uses flake-parts with one flake-scoped shield and two configurations: `alpha` decrypts its configuration-scoped shield, and `beta` declares a shield file that does not exist. Both use the pre-configured NixOS module and read the shared shield's domain. The committed [throwaway master identity](examples/consumer/master-identities/throwaway.txt) protects nothing: it is public test data, must not be reused, and is not a leaked credential.

From a checkout of this repository:

```sh
nix run .#nix -- eval --json \
  --no-write-lock-file \
  --override-input nixos-shields . \
  ./examples/consumer#nixosConfigurations.alpha.config.age.shields.values
```

Replace the final attribute with `#sharedShield` for the flake-scoped value or `#shields` for the manifest. See the [example README](examples/consumer/README.md) for its layout and the deliberately missing shield.

## Decrypt cache

Decrypted shields are kept in a per-user directory so that an unchanged shield is not decrypted, and a hardware identity not prompted, on every evaluation. Each entry is keyed by the shield file's content hash and base name, so a changed file gets a new entry and the old one stays until the directory is cleared. The directory holds plaintext: it is created with mode 0700 and refused when owned by another user, but the values are readable to anyone with the account.

By default the decrypt cache lives at `/var/tmp/nixos-shields-<uid>`. `NIXOS_SHIELDS_CACHE_DIR` moves it, for a tmpfs or a sandbox:

```sh
NIXOS_SHIELDS_CACHE_DIR=/run/user/1000/nixos-shields \
  nix build .#nixosConfigurations.beta.config.system.build.toplevel
```

To clear the decrypt cache:

```sh
nixos-shields clean
```

The `/var/tmp` default is a provisional choice: it survives reboots, which is what keeps a hardware identity quiet across sessions, at the cost of plaintext outliving the session. It may be revisited; only the override and this note ship for now.

## Contributing

Read the [glossary](CONTEXT.md) and relevant [ADRs](docs/adr/) before changing code; [AGENTS.md](AGENTS.md) points to the contributor workflows. User-visible changes belong in [CHANGELOG.md](CHANGELOG.md)'s Unreleased section.

```sh
nix develop
```

The development shell provides the kit's wrapped Nix, nix-unit, the formatter, the linters, and rage. With [nix-direnv](https://github.com/nix-community/nix-direnv), the tracked `.envrc` loads it on entering the checkout. Development outputs live in the `dev` flake-parts partition, so consumers never evaluate them.

Format with `nix fmt`. The `formatting` check fails when the formatter would change a file, and the `lint` check runs statix, deadnix, shellcheck, and actionlint; both run in `nix flake check`.

CI builds the checks on x86_64-linux. aarch64-linux and aarch64-darwin outputs are declared but are not tested by CI.

## Checks

```sh
nix flake check
```

The `integration` check runs the wrapped Nix inside the build sandbox. It evaluates `lib.importShield` on a fixture encrypted to an identity generated at check time, including through a consumer's combined extra-builtins file supplied to `lib.mkNix`. It then evaluates the example consumer, asserting the manifest's relative locations, flake-scoped values, `alpha`'s configuration-scoped values, and that `beta` fails naming its missing file. It doubles as the ABI canary: it rebuilds whenever the Nix or the plugin changes.

The `cli` check copies the example into a writable directory and drives the packaged tool. It covers text and JSON listings, configuration filtering, local directory selection, unchanged and changed edits, creating a missing shield, editor failure and temporary-file cleanup, encryption to all master identities, rotation to a second identity verified through wrapped Nix, and decrypt-cache cleanup.

The `tests` check runs the [nix-unit](https://github.com/nix-community/nix-unit) suites under `tests/suites` without the plugin, against the flake's public outputs:

- `nixosModule` drives the option tree through `evalModules`. It covers types, defaults, `values` being read-only, `dir` being required when referenced, and the failures a missing file or an empty identity list produce.
- `flakeModule` evaluates the flake-parts option tree and the pre-configured NixOS module. It covers relative manifest locations, option types, read-only fields, inherited and overridden defaults, selecting configurations from another output, and importing the pre-configured module beside `nixosModules.default`. It also checks `lib.mkManifest` directly for plain flakes.

From the development shell, run the suites directly with the flake's locked inputs, or select one with `--attr`:

```sh
nix-unit tests/entrypoint.nix
nix-unit tests/entrypoint.nix --attr nixosModule
```

The `decrypt-cache` check drives the cache script directly with a throwaway master identity and a counting wrapper around `rage` in place of the real one. It asserts that a miss decrypts, a hit does not (a copy of the same file elsewhere included), a changed file gets its own entry, `--print-out-path` names the entry, and the override moves the directory.

The `formatting` and `lint` checks run the formatter and linters against a copy of the source, as described in [Contributing](#contributing).
