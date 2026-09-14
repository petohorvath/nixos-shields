# Agent instructions

## Agent skills

### Domain docs

Before exploring or changing code, read the glossary in [CONTEXT.md](CONTEXT.md) and the relevant [ADRs](docs/adr/). Read [domain guidance](docs/agents/domain.md) for vocabulary requirements and ADR conflict handling.

### Issue tracker

Before working with issues or specs, read the [issue tracker workflow](docs/agents/issue-tracker.md). Issues are tracked as GitHub Issues via the `gh` CLI.

### Triage labels

Before triaging issues or applying triage roles, read the [triage label mapping](docs/agents/triage-labels.md). Use the canonical role-to-label mapping defined there.

## Development and validation

- Before implementation, read [Contributing](README.md#contributing) for development-shell setup, formatting, Git hooks, and changelog policy.
- Before choosing validation for code changes, read [Checks](README.md#checks) for the check command and coverage.
- When changing Nix or nix-plugins, read [Supported Nix version and plugin ABI](README.md#supported-nix-version-and-plugin-abi) for the required version pairing.
- Before changing example fixtures or integration expectations, read the [example consumer README](examples/consumer/README.md) for the throwaway master identity and deliberately missing shield file.
