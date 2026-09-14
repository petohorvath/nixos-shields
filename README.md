# nixos-shields

Evaluation-time encrypted Nix expressions. A shield keeps identifying configuration values (domain names, real usernames, MAC addresses, disk serials) out of a public git repository while Nix can still read them during evaluation.

## Security boundary

A shield is not a secret. Its decrypted values land in the Nix store of every machine that evaluates or deploys the configuration, and in the per-user decrypt cache on disk. Anything that must stay confidential after deployment (passwords, tokens, private keys) belongs in a runtime secret manager such as agenix or sops-nix, never in a shield.

## Shields

A shield is a Nix expression stored age-encrypted in git and decrypted when Nix evaluates it. Its file name ends in `.nix.age`. It is encrypted to every master identity of the repository (a YubiKey plugin identity, an SSH key, or a plain age key), so any one of them can open it. `CONTEXT.md` holds the full glossary; `docs/adr/0001` records why decryption happens at evaluation time.

## Supported Nix version

The shield builtin is provided by [nix-plugins](https://github.com/shlevy/nix-plugins), which must be compiled against the exact Nix that loads it. The kit builds it against the Nix 2.34 series from nixpkgs (`nixVersions.nix_2_34`). A compatibility patch, `packages/nix-plugins/nix-2.34.patch`, is carried in-kit until an upstream nix-plugins release builds against that Nix. A newer Nix or a newer nix-plugins may make the patch unnecessary, or need new hunks.

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

Minimal wiring, with each configuration reading `<dir>/<name>.nix.age`:

```nix
{
  inputs.nixos-shields.url = "github:petohorvath/nixos-shields";

  outputs = { nixpkgs, nixos-shields, ... }: {
    nixosConfigurations.alpha = nixpkgs.lib.nixosSystem {
      modules = [
        nixos-shields.nixosModules.default
        ({ config, ... }: {
          age.shields = {
            masterIdentities = [ ./master-identities/yubikey-1.txt ];
            dir = ./shields;
            files.facts = config.age.shields.dir + "/alpha.nix.age";
          };
          networking.domain = config.age.shields.values.facts.domain;
        })
      ];
    };
  };
}
```

Reading a value needs the wrapped Nix, so the builtin is loaded; without it evaluation fails naming `lib.mkNix`.

## flake-parts module

Import `nixos-shields.flakeModule` in a flake-parts flake to declare flake-scoped shields and share defaults with configurations. The module uses the libraries supplied by the consumer's flake-parts; it introduces no additional flake input.

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `shields.dir` | path | none | Shield directory, passed to the pre-configured NixOS module. |
| `shields.masterIdentities` | list of paths | `[ ]` | Identities used for flake-scoped shields and as configuration defaults. |
| `shields.files` | attribute set of paths | `{ }` | Flake-scoped shield files by name. |
| `shields.values` | attribute set, read-only | derived | Decrypted flake-scoped values, read lazily before any configuration evaluates. |
| `shields.configurations` | attribute set of evaluated configurations | `config.flake.nixosConfigurations` | Configurations whose shield files enter the manifest. Override when your configurations live elsewhere. |
| `shields.nixosModule` | module, read-only | derived | The default NixOS module with directory and identities applied using `mkDefault`. Ordinary configuration assignments override them. |

Inside the module passed to `flake-parts.lib.mkFlake`:

```nix
{ config, ... }:
{
  imports = [ nixos-shields.flakeModule ];
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
        # The configuration's other NixOS settings go here.
      })
    ];
  };
}
```

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

## Example consumer

`examples/consumer` uses flake-parts with one flake-scoped shield and two configurations: `alpha` decrypts its configuration-scoped shield, and `beta` declares a shield file that does not exist. Both use the pre-configured NixOS module and read the shared shield's domain. The committed throwaway identity protects nothing and is labelled as such in the example's README. That README also shows how to evaluate the example against a checkout of the kit.

## Decrypt cache

Decrypted shields are kept in a per-user directory so that an unchanged shield is not decrypted, and a hardware identity not prompted, on every evaluation. Each entry is keyed by the shield file's content hash and base name, so a changed file gets a new entry and the old one stays until the directory is cleared. The directory holds plaintext: it is created with mode 0700 and refused when owned by another user, but the values are readable to anyone with the account.

By default the decrypt cache lives at `/var/tmp/nixos-shields-<uid>`. `NIXOS_SHIELDS_CACHE_DIR` moves it, for a tmpfs or a sandbox:

```sh
NIXOS_SHIELDS_CACHE_DIR=/run/user/1000/nixos-shields \
  nix build .#nixosConfigurations.beta.config.system.build.toplevel
```

To clear the decrypt cache, remove the directory:

```sh
rm -rf "${NIXOS_SHIELDS_CACHE_DIR:-/var/tmp/nixos-shields-$UID}"
```

The `/var/tmp` default is a provisional choice: it survives reboots, which is what keeps a hardware identity quiet across sessions, at the cost of plaintext outliving the session. It may be revisited; only the override and this note ship for now.

## Checks

```sh
nix flake check
```

The integration check runs the wrapped Nix inside the build sandbox. It evaluates `lib.importShield` on a fixture encrypted to an identity generated at check time, including through a consumer's combined extra-builtins file supplied to `lib.mkNix`. It then evaluates the example consumer, asserting the manifest's relative locations, flake-scoped values, `alpha`'s configuration-scoped values, and that `beta` fails naming its missing file. It doubles as the ABI canary: it rebuilds whenever the Nix or the plugin changes.

The NixOS module check drives the option tree through `evalModules` without the plugin. It covers types, defaults, `values` being read-only, `dir` being required when referenced, and the failures a missing file or an empty identity list produce.

The flake module check evaluates the flake-parts option tree and the pre-configured NixOS module without the plugin. It covers relative manifest locations, option types, read-only fields, inherited and overridden defaults, and selecting configurations from another output. It also checks `lib.mkManifest` directly for plain flakes.

The decrypt cache check drives the cache script directly with a throwaway master identity and a counting wrapper around `rage` in place of the real one. It asserts that a miss decrypts, a hit does not (a copy of the same file elsewhere included), a changed file gets its own entry, `--print-out-path` names the entry, and the override moves the directory.
