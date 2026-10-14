# Changelog

## 0.2.0 - Unreleased

### Added

- `packages.default`, the `nixos-shields` command-line tool.
- `flakeModules.default`, the flake-parts module.

### Changed

- Every shield belongs to a configuration, and every configuration declares its own master identities, as with agenix-rekey. The manifest's `masterIdentities`, from `lib.mkManifest` and `flakeModules.default`, combines every configuration's `age.shields.masterIdentities`, each identity once, and `nixos-shields edit` and `rekey` encrypt every shield to all of them. Share master identities through a NixOS module imported by each configuration, share data by declaring one shield file in several configurations, and read a configuration's values from outside it through `nixosConfigurations.<name>.config.age.shields.values`.
- `nixos-shields list` headings name each configuration as `Configuration <name>:`.
- Unit tests run under nix-unit and can be run directly from the development shell.
- Formatting and lint are flake checks, run by `nix flake check` and CI.
- The `nixpkgs` input tracks `nixos-26.05` instead of `nixos-unstable`, locked to the nixos-project-policy v0.5.1 stable pin; consumers that do not make it follow their own nixpkgs get the stable release. x86_64-darwin stays undeclared.
- CI calls the shared project policy `v0.6` workflow instead of its own. It runs on x86_64-linux and aarch64-linux and tests the locked nixpkgs and the policy's stable and unstable pins; the required statuses become `Policy / Check (<system>)` and `Policy / Tests (locked|stable|unstable, <system>)`. There are no VM tests, so no `Policy / VM tests (locked|stable|unstable, <system>)` status is required.

### Removed

- The `flakeModule` output; import `flakeModules.default` instead.
- The `git-hooks` input; drop any follows or overrides of `nixos-shields/git-hooks`.
- The development-shell Git hooks.
- Flake-scoped shields. `flakeModules.default` loses the `shields.dir`, `shields.masterIdentities`, `shields.files`, `shields.values`, and `shields.nixosModule` options; import `nixosModules.default` in each configuration instead, and keep `shields.configurations`.
- The `masterIdentities` and `files` arguments of `lib.mkManifest`, which now takes only `self` and `configurations`.
- The manifest's top-level `files` field.
- Bare `<name>` addresses in `nixos-shields`; address every shield as `<configuration>:<name>`.
- The flake-scoped group of `nixos-shields list`, in its text output and the `files` field of its JSON output.

## 0.1.0 - 2026-09-14

### Added

- Evaluation-time imports of age-encrypted Nix expressions through `lib.importShield`, with a content-addressed, per-user decrypt cache and `NIXOS_SHIELDS_CACHE_DIR` override.
- Wrapped Nix 2.34 binary set from `lib.mkNix` and the `nix` package, a matching nix-plugins build with an in-kit compatibility patch, and composable extra builtins.
- NixOS module for configuration-scoped shields, flake-parts module for flake-scoped shields and shared defaults, and `lib.mkManifest` for plain flakes.
- `nixos-shields list`, `edit`, `rekey`, and `clean`, with manifest addresses, JSON listings, encryption to every master identity, and unchanged-edit preservation.
- Example consumer with a committed throwaway master identity, both shield scopes, and a deliberately missing shield file.
- Unit and sandbox integration checks, CI for formatting and x86_64-linux checks, and development-shell hooks that format on commit and run checks on push.
- Adoption recipes, shield-versus-secret guidance, glossary, and the evaluation-time decryption ADR.

Outputs are declared for x86_64-linux, aarch64-linux, and aarch64-darwin; x86_64-linux is tested. Shield values are readable in the Nix store and decrypt cache and must not contain runtime credentials.
