# Example consumer

A flake-parts flake that consumes `nixos-shields.flakeModules.default` to publish its manifest. Both NixOS configurations import a common module that adds `nixosModules.default` and declares the shield directory and master identity, and both declare one shared shield file.

## Throwaway identity

`master-identities/throwaway.txt` is a throwaway age identity, committed on purpose so the example evaluates anywhere. It protects nothing, and both shield files contain only example values. Do not report it as leaked, and do not reuse it.

## Layout

| Path | Role |
| --- | --- |
| `flake.nix` | Two configurations, `alpha` and `beta`, each reading `shields/<name>.nix.age` and `shields/shared.nix.age` |
| `master-identities/throwaway.txt` | The throwaway age identity every shield is encrypted to |
| `shields/shared.nix.age` | The shield both configurations declare, holding the shared domain `example.test` |
| `shields/alpha.nix.age` | `alpha`'s own shield |

`beta` declares `shields/beta.nix.age`, which does not exist: reading its `facts` value fails with a message naming that file, while its `shared` value reads normally. It shows what a fresh configuration without a shield looks like.

## Usage

Evaluation needs the wrapped Nix from the kit, so the shield builtin is loaded. From this directory, pointing the `nixos-shields` input at the checkout:

```sh
nix run ../..#nix -- eval --json \
  --override-input nixos-shields ../.. \
  .#nixosConfigurations.alpha.config.age.shields.values
```

prints `alpha`'s decrypted shield, and the same command for `beta` fails naming `shields/beta.nix.age`.

Replace the final attribute with `.#nixosConfigurations.beta.config.age.shields.values.shared` to read the shared shield through `beta`, or with `.#shields` to list the manifest. The manifest includes the relative locations of every configuration's shield files, including `beta`'s missing file, and can also be evaluated with ordinary Nix. Each configuration uses the shared domain in `networking.search`.

`.#deploy.nodes.alpha.hostname` reads `alpha`'s domain from outside the configuration, in the shape deploy-rs reads its nodes from. The example has no deploy-rs input or profiles; the attribute only shows where such a value comes from.

## Shield editing

```sh
rage --decrypt --identity master-identities/throwaway.txt shields/alpha.nix.age > alpha.nix
$EDITOR alpha.nix
rage --encrypt --identity master-identities/throwaway.txt --output shields/alpha.nix.age alpha.nix
rm alpha.nix
```
