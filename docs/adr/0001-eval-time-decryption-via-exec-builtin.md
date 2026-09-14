---
status: accepted
---

# Decrypt shields at evaluation time through an `exec` extra builtin

Shields exist to keep personally identifiable configuration out of git history, not to protect it at runtime; the values are needed while Nix evaluates a configuration (disk serials for disko, MAC addresses for interface naming, domains for vhosts), so a runtime secret mechanism cannot supply them. We decrypt at evaluation time by calling rage from an `exec` extra builtin provided by nix-plugins, and accept that the decrypted values land in the Nix store of every machine that evaluates or deploys the configuration.

## Considered Options

- **agenix / agenix-rekey / sops-nix (runtime secrets)**: values arrive as files on the target after activation, too late for evaluation-time consumers like disko or module options. Right tool for credentials, which shields explicitly are not.
- **git-crypt or a private repository**: hides the whole tree or requires a second repo; neither lets one public repository carry the configuration with only the identifying values withheld.
- **Plain Nix files listed in `.gitignore`**: not versioned, not shared between working copies, and silently missing on a fresh clone.
- **`exec` extra builtin with rage (chosen)**: versioned, encrypted at rest in git, decrypted on the developer's machine during evaluation, cached per content hash so a hardware identity is prompted once per file change.

## Consequences

- Every evaluation of a consumer flake needs a Nix binary that loads nix-plugins built against that exact Nix version; the kit ships the wrapped binary and carries the ABI patch until upstream nix-plugins catches up.
- Shield values are readable in `/nix/store` and in the decrypt cache on disk. Anything that must stay confidential after deployment is a secret, not a shield, and belongs in a runtime secret manager.
- Evaluation becomes impure in the sense of depending on an identity being present, so CI without a master identity cannot evaluate shielded configurations.
