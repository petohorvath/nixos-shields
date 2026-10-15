# Reference

The flake's public interface: its outputs, library functions, module options, and manifest format. [GLOSSARY.md](../GLOSSARY.md) defines the terms used here, and [cli.md](cli.md) documents the command-line tool.

## Flake outputs

The table lists the consumer-facing outputs. The `checks`, `devShells`, and `formatter` outputs come from the `dev` flake-parts partition and serve development only.

| Output | Content |
| --- | --- |
| `lib.importShield` | Decrypts one shield file |
| `lib.mkNix` | Builds a wrapped Nix |
| `lib.mkExtraBuiltinsFile` | Builds the kit's extra-builtins file |
| `lib.mkManifest` | Builds the manifest for plain flakes |
| `nixosModules.default` | The `age.shields` NixOS module |
| `flakeModules.default` | The flake-parts module |
| `packages.<system>.default` | The `nixos-shields` command-line tool, also `packages.<system>.nixos-shields` |
| `packages.<system>.nix` | The wrapped Nix with default arguments |
| `packages.<system>.nix-plugins` | The nix-plugins build the wrapped Nix loads |
| `packages.<system>.extra-builtins` | The kit's extra-builtins file |
| `packages.<system>.decrypt` | The decrypt script behind the builtin |

## Library functions

### `lib.importShield`

`importShield identities file` decrypts `file` with any of the master identities in the list `identities` and returns the value of the Nix expression it holds. `identities` takes the [entry forms](#master-identity-entries) of `age.shields.masterIdentities`; only the identity files are used, since a public key cannot decrypt. Before decrypting, it fails with a message naming the file when the file does not exist or the identity list is empty, and with a message naming `lib.mkNix` when the running Nix lacks the builtin.

```nix
nixos-shields.lib.importShield [ ./master-identities/yubikey-1.txt ] ./shields/beta.nix.age
```

### `lib.mkNix`

`mkNix` returns a Nix binary set whose every invocation loads the shield builtin. Each binary is wrapped individually with `NIX_CONFIG` set for that process only and argv[0] preserved, so `nix-store`, `nix-build`, and the other multi-call binaries keep their behaviour and nothing is exported into the caller's shell.

| Argument | Default | Meaning |
| --- | --- | --- |
| `pkgs` | required | The package set to build with |
| `nix` | `pkgs.nixVersions.nix_2_34` | The Nix package to wrap; a concrete series, never `pkgs.nix`, because the plugin must match its ABI |
| `extraConfig` | `""` | Extra `nix.conf` lines, such as `accept-flake-config = true`; the kit sets no such policy itself |
| `extraBuiltinsFile` | `lib.mkExtraBuiltinsFile { inherit pkgs; }` | The extra-builtins file to load; a replacement must keep `importShield` by importing the kit's file |

The result's `passthru` holds `extraBuiltinsFile`, `nix`, and `plugins`.

### `lib.mkExtraBuiltinsFile`

`mkExtraBuiltinsFile { pkgs }` builds the kit's extra-builtins file, which defines `importShield`.

### `lib.mkManifest`

`mkManifest` builds the manifest for a plain flake, without a flake-parts dependency. It reads only file declarations, so building it never decrypts a shield.

| Argument | Default | Meaning |
| --- | --- | --- |
| `self` | required | The consumer's flake, whose root anchors every location |
| `configurations` | `{ }` | Evaluated configurations by name; each contributes its `config.age.shields.files` and `masterIdentities` |

```nix
shields = nixos-shields.lib.mkManifest {
  inherit self;
  configurations = self.nixosConfigurations;
};
```

## NixOS module

`nixosModules.default` exposes a configuration's shields under `age.shields`. The module knows nothing about configuration names or directory layout: the consumer's wiring decides which file each configuration reads.

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `age.shields.masterIdentities` | list of [master identity entries](#master-identity-entries) | `[ ]` | Age identities, any one of which can decrypt every shield of the configuration, tried in order. Evaluating a shield with none set fails. The manifest adds them to the identities every shield is encrypted to. |
| `age.shields.dir` | path | none | The directory holding the shield files. The kit never reads it; it exists so the consumer's wiring can build file locations from it. |
| `age.shields.files` | attribute set of paths | `{ }` | Shield files by name. A file that does not exist fails evaluation with a message naming it. Several configurations can declare the same file, which then has an address in each. |
| `age.shields.values` | attribute set, read-only | derived | The decrypted value of each file in `files`, by name. Each value is decrypted only when something reads it. |

Configurations share `dir` and `masterIdentities` through a module of the consumer's own, imported by each of them. A flake that also uses agenix-rekey can assign `age.shields.masterIdentities = config.age.rekey.masterIdentities` there, since both options take the same entries. Outside a configuration, its values are readable as `nixosConfigurations.<name>.config.age.shields.values`, for example to give a deploy-rs node its hostname.

### Master identity entries

An entry of `age.shields.masterIdentities` uses the names of agenix-rekey's `age.rekey.masterIdentities`:

| Form | Meaning |
| --- | --- |
| A path, such as `./master-identities/yubikey-1.txt` | The identity file alone |
| `{ identity; pubkey; }` | The identity file, a path or an absolute path string, paired with its public key, a string; `pubkey` defaults to `null` |

The option reads back every entry as an attribute set, a path becoming `{ identity = <path>; pubkey = null; }`. Decryption uses only `identity`. When `pubkey` is set, `nixos-shields edit` and `rekey` encrypt to it instead of presenting the identity file, so a passphrase-protected identity or another person's YubiKey needs no prompt:

```nix
age.shields.masterIdentities = [
  ./master-identities/yubikey-1.txt
  {
    identity = ./master-identities/passphrase.age;
    pubkey = "age1...";
  }
];
```

A string that is not an absolute path fails evaluation.

## flake-parts module

`flakeModules.default` publishes the manifest as the `shields` flake output. It uses the libraries supplied by the consumer's flake-parts and introduces no flake input. Configurations import `nixosModules.default` themselves.

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `shields.configurations` | attribute set of evaluated configurations | `config.flake.nixosConfigurations` | Configurations whose shield files and master identities enter the manifest. Override it when the configurations live in another output. |

## Manifest

The manifest lists the master identities and each configuration's shield files. It is built without decrypting values or requiring the shield files to exist. Every location is a string relative to the consumer's flake root; a location outside that root fails evaluation with a message naming it. A configuration without the shields module appears with empty `files`.

`masterIdentities` combines every configuration's `age.shields.masterIdentities`, each identity once, in configuration name order. Each entry is an object with the identity file's location as `identity` and its public key as `pubkey`, or `null` when no configuration pairs it with one. Two configurations that pair one identity with different public keys fail evaluation with a message naming the identity. The command-line tool encrypts every shield to all of them, so an identity declared by any configuration opens every shield, including those of other configurations. A configuration without the shields module contributes no identities.

For the [example consumer](../examples/consumer), `nix eval --json .#shields` returns:

```json
{
  "configurations": {
    "alpha": {
      "files": { "facts": "shields/alpha.nix.age", "shared": "shields/shared.nix.age" }
    },
    "beta": {
      "files": { "facts": "shields/beta.nix.age", "shared": "shields/shared.nix.age" }
    }
  },
  "masterIdentities": [
    { "identity": "master-identities/throwaway.txt", "pubkey": null }
  ]
}
```

## Wrapped Nix

Nix has one `extra-builtins-file` setting. A consumer with builtins of its own builds the kit's file, imports it with the arguments nix-plugins supplies, merges its own builtins into the returned attribute set, and hands the combined file to `lib.mkNix`:

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

The result exposes both `builtins.extraBuiltins.importShield` and `builtins.extraBuiltins.consumerAnswer`. Give additions distinct names so they do not replace the kit's builtin.

## Nix version and plugin ABI

The shield builtin is provided by [nix-plugins](https://github.com/shlevy/nix-plugins), which must be compiled against the exact Nix that loads it. The kit builds it against the Nix 2.34 series from nixpkgs (`nixVersions.nix_2_34`). This ABI requirement is why the kit supplies a wrapped Nix together with the matching plugin, rather than loading the plugin into an arbitrary system Nix.

A [compatibility patch](../packages/nix-plugins/nix-2.34.patch) is carried in the kit until an upstream nix-plugins release builds against that Nix. A newer Nix or a newer nix-plugins may make the patch unnecessary, or need new hunks.

## Decrypt cache

Each decrypt cache entry is keyed by the shield file's content hash and base name, so an unchanged file is not decrypted again, even when a copy with the same base name lives elsewhere, and a changed file gets a new entry that coexists with the old one until the decrypt cache is removed. The decrypt cache directory is created with mode 0700 and refused when another user owns it. Decryption writes a partial file beside the entry and moves it into place, so an interrupted decryption never leaves a truncated entry.

The directory defaults to `/var/tmp/nixos-shields-<uid>`, and `NIXOS_SHIELDS_CACHE_DIR` overrides it.
