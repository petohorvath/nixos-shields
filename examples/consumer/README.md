# Example consumer

A plain flake (no flake-parts) that consumes nixos-shields as an input and declares one configuration-scoped shield per NixOS configuration.

## Throwaway identity

`master-identities/throwaway.txt` is a throwaway age identity, committed on purpose so the example evaluates anywhere. It protects nothing, and `shields/alpha.nix.age` holds nothing worth reading. Do not report it as leaked, and do not reuse it.

## Layout

| Path | Role |
| --- | --- |
| `flake.nix` | Two configurations, `alpha` and `beta`, each reading `shields/<name>.nix.age` |
| `master-identities/throwaway.txt` | The throwaway age identity every shield is encrypted to |
| `shields/alpha.nix.age` | The configuration-scoped shield of `alpha` |

`beta` declares `shields/beta.nix.age`, which does not exist: reading its values fails with a message naming that file. It shows what a fresh configuration without a shield looks like.

## Usage

Evaluation needs the wrapped Nix from the kit, so the shield builtin is loaded. From this directory, pointing the `nixos-shields` input at the checkout:

```sh
nix run ../..#nix -- eval --json \
  --override-input nixos-shields ../.. \
  .#nixosConfigurations.alpha.config.age.shields.values
```

prints `alpha`'s decrypted shield, and the same command for `beta` fails naming `shields/beta.nix.age`.

## Shield editing

```sh
rage --decrypt --identity master-identities/throwaway.txt shields/alpha.nix.age > alpha.nix
$EDITOR alpha.nix
rage --encrypt --identity master-identities/throwaway.txt --output shields/alpha.nix.age alpha.nix
rm alpha.nix
```
