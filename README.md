# nixos-shields

nixos-shields is a Nix flake that stores Nix expressions age-encrypted in git and decrypts them when Nix evaluates them. NixOS flakes in public repositories use it to keep identifying configuration, such as domain names, real usernames, MAC addresses, and disk serials, out of the published source while their configurations still read the values as ordinary options.

## Overview

A **shield** is one such encrypted expression, stored in a shield file whose name ends in `.nix.age`. Each shield is encrypted to every master identity of the repository, so any one of them can open it. A master identity is an age identity file: a YubiKey plugin identity stub, an SSH key, or a plain age key.

A shield is not a secret. Its decrypted values land in the Nix store of every machine that evaluates or deploys the configuration, and in a plaintext decrypt cache on disk. Passwords, tokens, private keys, and anything else that must stay confidential after deployment belong in a runtime secret manager such as agenix or sops-nix.

Shields have one of two scopes:

- A **flake-scoped shield** belongs to the flake as a whole and is readable before any configuration evaluates.
- A **configuration-scoped shield** belongs to one NixOS configuration and is readable through that configuration's `age.shields.values` option.

A plugin builtin decrypts shields during evaluation, so evaluation needs the kit's wrapped Nix, which loads that builtin. [ADR 0001](docs/adr/0001-eval-time-decryption-via-exec-builtin.md) records why decryption happens at evaluation time, and [GLOSSARY.md](GLOSSARY.md) defines the project's terms.

## Requirements

- Nix with flakes enabled to fetch the kit. The kit supplies its own wrapped Nix from the Nix 2.34 series for every evaluation that reads a shield, because the [nix-plugins](https://github.com/shlevy/nix-plugins) builtin must match the Nix that loads it. [Nix version and plugin ABI](docs/reference.md#nix-version-and-plugin-abi) explains the pairing.
- x86_64-linux or aarch64-linux, which CI tests. Outputs are also declared for aarch64-darwin, which CI does not test. x86_64-darwin is not declared, because nixpkgs drops it in 26.11.

## Install

Add the flake as an input:

```nix
inputs.nixos-shields = {
  url = "github:petohorvath/nixos-shields";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

The flake's default package is the `nixos-shields` command-line tool, and its `nix` package is the wrapped Nix:

```sh
nix shell github:petohorvath/nixos-shields github:petohorvath/nixos-shields#nix
```

Before declaring shields, commit at least one master identity file under the flake root. Every location the tool reads, master identities included, must lie inside the flake root.

## Usage

The [example consumer](examples/consumer) holds a flake-scoped shield, a configuration `alpha` with its own shield, and a configuration `beta` whose shield file is deliberately missing. Its master identity is a committed throwaway key that protects nothing. From a checkout of this repository, the wrapped Nix reads `alpha`'s decrypted shield:

```console
$ nix run .#nix -- eval --json --no-write-lock-file \
    --override-input nixos-shields . \
    ./examples/consumer#nixosConfigurations.alpha.config.age.shields.values
{"facts":{"domain":"alpha.example.test","macAddress":"02:00:00:00:00:01"}}
```

The command-line tool lists the shields the example declares without decrypting them:

```console
$ nix run . -- --flake examples/consumer list
Flake-scoped shields:
  shared [exists] shields/shared.nix.age
Configuration-scoped shields (alpha):
  alpha:facts [exists] shields/alpha.nix.age
Configuration-scoped shields (beta):
  beta:facts [missing] shields/beta.nix.age
Total: 3; exists: 2; missing: 1
```

The [example README](examples/consumer/README.md) describes its layout and the other attributes to evaluate.

## Declare shields in a flake

`nixosModules.default` adds the `age.shields` options to a configuration. `lib.mkManifest` publishes the `shields` flake output, the manifest from which the command-line tool learns each shield's address and file. This `flake.nix` declares one configuration-scoped shield and reads its `domain` into an ordinary option:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-shields = {
      url = "github:petohorvath/nixos-shields";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-shields,
      ...
    }:
    let
      masterIdentities = [ ./master-identities/yubikey-1.txt ];
    in
    {
      shields = nixos-shields.lib.mkManifest {
        inherit self masterIdentities;
        configurations = self.nixosConfigurations;
      };

      nixosConfigurations.alpha = nixpkgs.lib.nixosSystem {
        modules = [
          nixos-shields.nixosModules.default
          (
            { config, ... }:
            {
              age.shields = {
                inherit masterIdentities;
                dir = ./shields;
                files.facts = config.age.shields.dir + "/alpha.nix.age";
              };
              networking.domain = config.age.shields.values.facts.domain;
              nixpkgs.hostPlatform = "x86_64-linux";
              system.stateVersion = "26.05";
            }
          )
        ];
      };
    };
}
```

The shield file need not exist yet: `nixos-shields edit alpha:facts` creates it. Reading a value with a Nix that lacks the builtin fails with a message naming `lib.mkNix`.

### With flake-parts

`flakeModules.default` declares flake-scoped shields and passes the shield directory and master identities to each configuration through the pre-configured `shields.nixosModule`. It also publishes the manifest, so the flake needs no `lib.mkManifest` call:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    nixos-shields = {
      url = "github:petohorvath/nixos-shields";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
  };

  outputs =
    inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { config, ... }:
      {
        imports = [ inputs.nixos-shields.flakeModules.default ];
        systems = [ "x86_64-linux" ];

        shields = {
          dir = ./shields;
          masterIdentities = [ ./master-identities/yubikey-1.txt ];
          files.shared = ./shields/shared.nix.age;
        };

        flake.nixosConfigurations.alpha = nixpkgs.lib.nixosSystem {
          modules = [
            config.shields.nixosModule
            (
              { config, ... }:
              {
                age.shields.files.facts = config.age.shields.dir + "/alpha.nix.age";
                networking.domain = config.age.shields.values.facts.domain;
                nixpkgs.hostPlatform = "x86_64-linux";
                system.stateVersion = "26.05";
              }
            )
          ];
        };
      }
    );
}
```

The flake-scoped value `config.shields.values.shared` is readable in the outer flake-parts module, before any configuration evaluates. Inside a NixOS module, `config` refers to the configuration, so capture the shared value in the outer module or pass it through `specialArgs`.

[docs/reference.md](docs/reference.md) lists every option of both modules, the library functions, and the manifest format.

## Edit shields

Run the tool in the consumer's flake checkout, or pass `--flake <directory>`. A shield's address is its name for a flake-scoped shield, such as `shared`, or `<configuration>:<name>` for a configuration-scoped one, such as `alpha:facts`:

```sh
nixos-shields list
EDITOR='code --wait' nixos-shields edit alpha:facts
nixos-shields rekey
```

`edit` decrypts the shield to a temporary file outside the checkout, runs `$EDITOR` on it, and encrypts a changed result to every master identity. A declared shield file that does not exist starts from `{}`. After a change to the declared master identities, `rekey` encrypts every shield to the new list. [docs/cli.md](docs/cli.md) covers every command, option, and the identity rotation procedure.

## Run Nix tools with the shield builtin

Evaluations that read a shield must run under the wrapped Nix. `nixos-rebuild`, `nixos-anywhere`, and `disko` carry their own Nix, so override their `nix` argument with the wrapped one. In a consumer's development shell, with `nixos-shields` bound to the flake input and `pkgs` to a Linux package set:

```nix
let
  nix = nixos-shields.lib.mkNix { inherit pkgs; };
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

The recipe overrides the nixpkgs packages; a tool's own flake may expose different override arguments. `lib.mkNix` also accepts extra `nix.conf` lines and a combined extra-builtins file for consumers with builtins of their own, as described in [Wrapped Nix](docs/reference.md#wrapped-nix).

## Decrypt cache

Decrypted shields are cached per user, so an unchanged shield is not decrypted again, and a hardware identity not prompted again, on every evaluation. The cache lives at `/var/tmp/nixos-shields-<uid>` and holds plaintext readable to the account that owns it. `NIXOS_SHIELDS_CACHE_DIR` moves it, for example to a tmpfs:

```sh
NIXOS_SHIELDS_CACHE_DIR=/run/user/1000/nixos-shields \
  nix build .#nixosConfigurations.alpha.config.system.build.toplevel
```

`nixos-shields clean` removes the cache. A changed shield file gets a new entry, and old entries remain until the cache is removed.

## Limitations

- Shield values are readable in the Nix store and the decrypt cache; shields cannot hold runtime credentials.
- The default decrypt cache in `/var/tmp` survives reboots, which keeps a hardware identity from prompting again, at the cost of plaintext outliving the session. The default is provisional and may change.
- Evaluation requires the kit's wrapped Nix 2.34. The nix-plugins build carries an [in-kit compatibility patch](packages/nix-plugins/nix-2.34.patch) for that series.
- A former master identity can still decrypt the shield file versions in git history.

## Contributing

Report bugs and ask questions in [GitHub Issues](https://github.com/petohorvath/nixos-shields/issues). [AGENTS.md](AGENTS.md) lists the development setup, required checks, and changelog policy, and [docs/testing.md](docs/testing.md) describes what each check covers.

## License

MIT. See [LICENSE](LICENSE).
