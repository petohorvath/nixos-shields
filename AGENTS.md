# Agent instructions

## Agent skills

### Issue tracker

Before working with issues or specs, read the [issue tracker workflow](docs/agents/issue-tracker.md). Issues are tracked as GitHub Issues via the `gh` CLI.

### Triage labels

Before triaging issues or applying triage roles, read the [triage label mapping](docs/agents/triage-labels.md). Use the canonical role-to-label mapping defined there.

### Domain docs

Before exploring or changing code, read the glossary in [GLOSSARY.md](GLOSSARY.md) and the relevant [ADRs](docs/adr/). Read [domain guidance](docs/agents/domain.md) for vocabulary requirements and ADR conflict handling.

## Development and validation

- Before choosing validation for code changes, read [Required checks](#required-checks) for the commands and [docs/testing.md](docs/testing.md) for what each check covers.
- When changing Nix or nix-plugins, read [Nix version and plugin ABI](docs/reference.md#nix-version-and-plugin-abi) for the required version pairing.
- When changing a public output, option, or command, keep [README.md](README.md), [docs/reference.md](docs/reference.md), and [docs/cli.md](docs/cli.md) consistent with it.
- Before changing example fixtures or integration expectations, read the [example consumer README](examples/consumer/README.md) for the throwaway master identity and deliberately missing shield file.
- Record user-visible changes in the topmost, unreleased section of [CHANGELOG.md](CHANGELOG.md). Its heading names the next version, which must be a minor or major bump when a change removes a public output.

## Required checks

The development shell, loaded by `nix develop` or by [nix-direnv](https://github.com/nix-community/nix-direnv) through the tracked `.envrc`, provides the kit's wrapped Nix, nix-unit, treefmt with every formatter and linter it runs, statix, and rage. Development outputs live in the `dev` flake-parts partition, so consumers never evaluate them.

```sh
nix fmt                                                           # fix a failing `treefmt` check
nix-unit --flake .#tests.systems.x86_64-linux                     # the nix-unit suites, for a fast loop
nix-unit --flake .#tests.systems.x86_64-linux.unit.nixos.module   # one suite
nix-unit --flake .#tests.systems.x86_64-linux.unit.nixos.module --attr testDefaults   # one test
nix flake check                                                   # every check
```

CI calls the shared [project policy](https://github.com/petohorvath/nixos-project-policy/blob/v0.6/POLICY.md#caller) workflow at `v0.6` from [`.github/workflows/check.yml`](.github/workflows/check.yml). On x86_64-linux and aarch64-linux, it checks the flake's inputs and public outputs, starts the development shell, and evaluates the formatter. With the locked nixpkgs and with the policy's stable and unstable pins, it evaluates every output and builds every `checks` entry. The policy lists the required statuses; a pull request merges only after they pass. To run the same checks locally from the repository root, as the policy's [local check](https://github.com/petohorvath/nixos-project-policy/blob/v0.6/README.md#local-check) describes:

```sh
nix run github:petohorvath/nixos-project-policy/v0.6 -- check .
nix run github:petohorvath/nixos-project-policy/v0.6 -- test . --nixpkgs locked
```

`test` also accepts `--nixpkgs stable` and `--nixpkgs unstable`. It needs a Nix whose `nix derivation show` reports format version 4, such as the development shell's Nix 2.34.
