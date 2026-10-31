# nixos-shields

nixos-shields is a Nix flake that stores Nix expressions age-encrypted in git and decrypts them when Nix evaluates them. NixOS flakes in public repositories use it to keep identifying configuration, such as domain names, real usernames, MAC addresses, and disk serials, out of the published source while their configurations still read the values as ordinary options.

## Overview

A **shield** is one such encrypted expression, stored in a shield file whose name ends in `.nix.age`. Every shield belongs to a NixOS configuration and is readable through that configuration's `age.shields.values` option. A master identity is an age identity file: a YubiKey plugin identity stub, an SSH key, or a plain age key. Each configuration declares its own master identities, as each agenix-rekey host does, and every shield is encrypted to those of all configurations combined, so any one of them can open any shield.

A shield is not a secret. Its decrypted values land in the Nix store of every machine that evaluates or deploys the configuration, and in a plaintext decrypt cache on disk. Passwords, tokens, private keys, and anything else that must stay confidential after deployment belong in a runtime secret manager such as agenix or sops-nix.

A plugin builtin decrypts shields during evaluation, so evaluation needs the kit's wrapped Nix, which loads that builtin. [ADR 0001](docs/adr/0001-eval-time-decryption-via-exec-builtin.md) records why decryption happens at evaluation time, [ADR 0002](docs/adr/0002-master-identities-follow-agenix-rekey.md) why master identities are declared per configuration, and [GLOSSARY.md](GLOSSARY.md) defines the project's terms.

## Requirements

- Nix with flakes enabled to fetch the kit. The kit supplies its own wrapped Nix from the Nix 2.34 series for every evaluation that reads a shield, because the [nix-plugins](https://github.com/shlevy/nix-plugins) builtin must match the Nix that loads it. [Nix version and plugin ABI](docs/reference.md#nix-version-and-plugin-abi) explains the pairing.
- x86_64-linux or aarch64-linux, which CI tests. Darwin is not supported.

## Install

Add the flake as an input:

```nix
inputs.nixos-shields = {
  url = "github:petohorvath/nixos-shields";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

The `treefmt-nix` input serves only the kit's development checks, so a consumer can drop it by adding `inputs.treefmt-nix.follows = "";` to the block.

The flake's default package is the `nixos-shields` command-line tool, and its `nix` package is the wrapped Nix:

```sh
nix shell github:petohorvath/nixos-shields github:petohorvath/nixos-shields#nix
```

Before declaring shields, create at least one master identity. A YubiKey or FIDO2 identity stub, or a passphrase-protected identity, can be committed under the flake root. Keep a plain age key or an SSH key outside the flake root, for example under the home directory, and declare it as an absolute path string, so it is never committed or copied into the Nix store. Shield files must lie inside the flake root.

## Usage

The [example consumer](examples/consumer) holds two configurations that share one shield file, `alpha` with a shield of its own, and `beta` whose own shield file is deliberately missing. Its master identity is a committed throwaway identity that protects nothing. From a checkout of this repository, the wrapped Nix reads `alpha`'s decrypted shield:

```console
$ nix run .#nix -- eval --json --no-write-lock-file \
    --override-input nixos-shields . \
    ./examples/consumer#nixosConfigurations.alpha.config.age.shields.values
{"facts":{"domain":"alpha.example.test","macAddress":"02:00:00:00:00:01"},"shared":{"domain":"example.test"}}
```

The command-line tool lists the shields the example declares without decrypting them:

```console
$ nix run . -- --flake examples/consumer list
Configuration alpha:
  alpha:facts [exists] shields/alpha.nix.age
  alpha:shared [exists] shields/shared.nix.age
Configuration beta:
  beta:facts [missing] shields/beta.nix.age
  beta:shared [exists] shields/shared.nix.age
Total: 4; exists: 3; missing: 1
```

The example's `nixos-shields` input is not locked, so the tool evaluates the example's manifest against the published kit and needs network access. The [example README](examples/consumer/README.md) describes its layout and the other attributes to evaluate.

## Declare shields in a flake

`nixosModules.default` adds the `age.shields` options to a configuration. `lib.mkManifest` publishes the `shields` flake output, the manifest from which the command-line tool learns each shield's address and file. This `flake.nix` declares one shield and reads its `domain` into an ordinary option:

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
    {
      shields = nixos-shields.lib.mkManifest {
        inherit self;
        configurations = self.nixosConfigurations;
      };

      nixosConfigurations.alpha = nixpkgs.lib.nixosSystem {
        modules = [
          nixos-shields.nixosModules.default
          (
            { config, ... }:
            {
              age.shields = {
                masterIdentities = [ ./master-identities/yubikey-1.txt ];
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

`flakeModules.default` publishes the manifest from the flake's configurations, so the flake needs no `lib.mkManifest` call. A module of the consumer's own shares the shield directory and master identities between configurations:

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
      let
        commonModule = {
          imports = [ inputs.nixos-shields.nixosModules.default ];
          age.shields = {
            dir = ./shields;
            masterIdentities = [ ./master-identities/yubikey-1.txt ];
          };
        };
      in
      {
        imports = [ inputs.nixos-shields.flakeModules.default ];
        systems = [ "x86_64-linux" ];

        flake.nixosConfigurations.alpha = nixpkgs.lib.nixosSystem {
          modules = [
            commonModule
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

A flake that also uses agenix-rekey can assign `age.shields.masterIdentities = config.age.rekey.masterIdentities` in the common module.

A master identity can be paired with its public key, as in agenix-rekey. `nixos-shields edit` and `rekey` then encrypt to the key instead of presenting the identity file, so a passphrase-protected identity or a teammate's YubiKey needs no prompt:

```nix
age.shields.masterIdentities = [
  {
    identity = ./master-identities/passphrase.age;
    pubkey = "age1...";
  }
];
```

A YubiKey or FIDO2 identity stub needs no `pubkey`: when encrypting, `nixos-shields` [reads it](docs/cli.md#public-keys-from-identity-stubs) from the stub's `Recipient:` or `public key:` comment, so encrypting never touches the hardware.

A master identity outside the flake root is an absolute path string. Plain keys belong there, since a path inside the flake root is committed and copied into the Nix store with the flake:

```nix
age.shields.masterIdentities = [
  ./master-identities/yubikey-1.txt
  "/home/alice/.config/age/shields.txt"
];
```

`age.shields.extraEncryptionPubkeys` lists public keys that every shield is also encrypted to and that are never used to decrypt, such as an offline backup key. An entry is a public key string, or a recipients file given as a path or an absolute path string:

```nix
age.shields.extraEncryptionPubkeys = [
  "age1..."
  ./recipients/team.txt
];
```

[docs/reference.md](docs/reference.md) lists every option of both modules, the library functions, and the manifest format.

### Share a shield between configurations

Declare the same shield file in each configuration that reads it. Every shield is encrypted to the master identities of all configurations, so each one can decrypt it, and it has one address per configuration, such as `alpha:shared` and `beta:shared`:

```nix
{ config, ... }:
{
  age.shields.files.shared = config.age.shields.dir + "/shared.nix.age";
  networking.search = [ config.age.shields.values.shared.domain ];
}
```

### Read values outside a configuration

A configuration's values are readable from elsewhere in the flake through `nixosConfigurations.<name>.config.age.shields.values`. This deploy-rs node takes its hostname from `alpha`'s shield:

```nix
deploy.nodes.alpha = {
  hostname = self.nixosConfigurations.alpha.config.age.shields.values.facts.domain;
  profiles.system.path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.alpha;
};
```

Reading the hostname decrypts only `alpha`'s `facts` shield, and needs the wrapped Nix like any other read.

## Edit shields

Run the tool in the consumer's flake checkout, or pass `--flake <directory>`. A shield's address is `<configuration>:<name>`, such as `alpha:facts`:

```sh
nixos-shields list
EDITOR='code --wait' nixos-shields edit alpha:facts
nixos-shields rekey
```

`edit` decrypts the shield to a temporary file outside the checkout, runs `$EDITOR` on it, and encrypts a changed result to the master identities of every configuration. A declared shield file that does not exist starts from `{}`. After a change to the declared master identities, `rekey` encrypts every shield to the new list. [docs/cli.md](docs/cli.md) covers every command, option, and the identity rotation procedure.

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

Keep these overrides in the consumer; they are not kit outputs. The recipe overrides the nixpkgs packages; a tool's own flake may expose different override arguments. `lib.mkNix` also accepts extra `nix.conf` lines and a consumer's own builtins, as described in [Extra builtins](docs/reference.md#extra-builtins).

## Decrypt cache

Decrypted shields are kept in a per-user decrypt cache, so an unchanged shield is not decrypted again, and a hardware identity not prompted again, by evaluation, `nixos-shields edit`, or `nixos-shields rekey`. The decrypt cache lives at `/var/tmp/nixos-shields-<uid>` and holds plaintext readable to the account that owns it. `NIXOS_SHIELDS_CACHE_DIR` moves it, for example to a tmpfs:

```sh
NIXOS_SHIELDS_CACHE_DIR=/run/user/1000/nixos-shields \
  nix build .#nixosConfigurations.alpha.config.system.build.toplevel
```

`nixos-shields clean` removes the decrypt cache. [Decrypt cache](docs/reference.md#decrypt-cache) describes how entries are keyed.

## Limitations

- The default decrypt cache in `/var/tmp` survives reboots, which keeps a hardware identity from prompting again, at the cost of plaintext outliving the session. The default is provisional and may change.
- A former master identity can still decrypt the shield file versions in git history.

## Contributing

Report bugs and ask questions in [GitHub Issues](https://github.com/petohorvath/nixos-shields/issues). Pull requests target `main` and are squash-merged after the CI checks pass and a maintainer approves. [AGENTS.md](AGENTS.md) lists the development setup, required checks, and changelog policy, and [docs/testing.md](docs/testing.md) describes what each check covers.

## License

MIT. See [LICENSE](LICENSE).
