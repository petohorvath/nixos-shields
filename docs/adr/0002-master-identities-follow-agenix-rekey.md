---
status: accepted
---

# Master identities follow agenix-rekey; flake-scoped shields are dropped

Every shield belongs to a configuration, and every configuration declares its own master identities in `age.shields.masterIdentities`, as every agenix-rekey host owns its secrets and `age.rekey.masterIdentities`. The manifest combines the identities of all configurations, and the command-line tool encrypts every shield to that combined set. We dropped flake-scoped shields, with the flake-wide identity list they needed, because that list could disagree with the configurations' lists: `edit` then succeeded and the configuration failed to evaluate. Data shared by several configurations is served by declaring one shield file in each of them, and a configuration's values are read from outside it through `nixosConfigurations.<name>.config.age.shields.values`, for example as a deploy-rs hostname.

## Considered Options

- **Flake-wide list as the only source**: configurations would inherit it, but plain flakes would still repeat it in every configuration, and an identity added to one configuration would still be missing from encryption.
- **Validate that every configuration's identities appear in the flake-wide list**: catches the mismatch, but keeps three places to declare identities and a second scope that agenix-rekey users do not expect.
- **Identities per configuration, combined for encryption (chosen)**: one list per configuration is the only source of truth, and lists that drift apart can no longer produce a shield that a configuration cannot read.

## Consequences

- Any configuration's master identity opens every shield in the flake, as in agenix-rekey. Consumers who need confidentiality between configurations need separate flakes.
- A value is no longer readable before any configuration evaluates; reading one evaluates the configuration that declares it. Decryption still happens at evaluation time, as [ADR 0001](0001-eval-time-decryption-via-exec-builtin.md) records.
- A consumer shares identities between configurations through a NixOS module of its own, and one using agenix-rekey can assign `age.shields.masterIdentities = config.age.rekey.masterIdentities`.
