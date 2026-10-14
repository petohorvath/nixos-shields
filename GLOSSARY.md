# nixos-shields

Evaluation-time encrypted Nix expressions that keep personally identifiable configuration (domain names, real usernames, MAC addresses, disk serials) out of a git repository while staying readable in the Nix store.

## Language

**Shield**:
A Nix expression stored encrypted in git and decrypted when Nix evaluates it. Every shield belongs to a configuration. Its values are ordinary configuration, not credentials: they end up readable in the Nix store.
_Avoid_: Secret, evaluation-time secret, encrypted config

**Shield file**:
The on-disk form of a shield, an age-encrypted file whose name ends in `.nix.age`.
_Avoid_: Age file, encrypted file

**Secret**:
A runtime credential (password, token, private key) that must never reach the Nix store. Out of scope here; the term exists only to mark the boundary with a shield.
_Avoid_: Using "secret" for anything a shield holds

**Master identity**:
An age identity file able to decrypt every shield in a repository: a YubiKey plugin identity stub, an SSH key, or a plain age key. Each configuration declares its own, and every shield is encrypted to those of all configurations combined, so any one of them can open any shield.
_Avoid_: Key, recipient, pubkey

**Configuration**:
An evaluated NixOS system that can own shields. The consumer decides which attribute set holds them.
_Avoid_: Host, node, machine

**Manifest**:
The flake's declared inventory of shields: the master identities of all configurations combined and each configuration's shield files, with file locations relative to the flake root.
_Avoid_: Index, registry, catalogue

**Address**:
The name by which a shield is referred to on the command line: `<configuration>:<name>`. A shield file declared by several configurations has one address in each.
_Avoid_: Path, identifier, id

**Decrypt cache**:
The per-user directory holding decrypted shield contents so that an unlocked shield is not decrypted, and a hardware identity not prompted, again on every evaluation. Holds plaintext.
_Avoid_: Cache, tmp, temp files

**Wrapped nix**:
A Nix binary set whose configuration loads the shield builtin on every invocation, without exporting anything into the caller's environment.
_Avoid_: Plugin nix, devshell nix, patched nix
