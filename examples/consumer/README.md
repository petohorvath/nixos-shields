# Example consumer

A flake-parts flake that consumes `nixos-shields.flakeModule`, declares a flake-scoped shield, and imports `shields.nixosModule` in each NixOS configuration to inherit the directory and master identities.

## Throwaway identity

`master-identities/throwaway.txt` is a throwaway age identity, committed on purpose so the example evaluates anywhere. It protects nothing, and both shield files contain only example values. Do not report it as leaked, and do not reuse it.

## Layout

| Path | Role |
| --- | --- |
| `flake.nix` | Two configurations, `alpha` and `beta`, each reading `shields/<name>.nix.age` |
| `master-identities/throwaway.txt` | The throwaway age identity every shield is encrypted to |
| `shields/shared.nix.age` | The flake-scoped shield, holding the shared domain `example.test` |
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

Replace the final attribute with `.#sharedShield` to read the flake-scoped value before either configuration evaluates, or with `.#shields` to list the manifest. The manifest includes relative locations for both scopes, including `beta`'s missing file, and can also be evaluated with ordinary Nix. Each configuration uses the shared domain in `networking.search`.

## Shield editing

```sh
rage --decrypt --identity master-identities/throwaway.txt shields/alpha.nix.age > alpha.nix
$EDITOR alpha.nix
rage --encrypt --identity master-identities/throwaway.txt --output shields/alpha.nix.age alpha.nix
rm alpha.nix
```
