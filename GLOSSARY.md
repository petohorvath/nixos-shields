# nixos-shields

Evaluation-time encrypted Nix expressions that keep personally identifiable configuration (domain names, real usernames, MAC addresses, disk serials) out of a git repository while staying readable in the Nix store.

## Language

**Shield**:
A Nix expression stored encrypted in git and decrypted when Nix evaluates it. Its values are ordinary configuration, not credentials: they end up readable in the Nix store.
_Avoid_: Secret, evaluation-time secret, encrypted config

**Shield file**:
The on-disk form of a shield, an age-encrypted file whose name ends in `.nix.age`.
_Avoid_: Age file, encrypted file

**Secret**:
A runtime credential (password, token, private key) that must never reach the Nix store. Out of scope here; the term exists only to mark the boundary with a shield.
_Avoid_: Using "secret" for anything a shield holds

**Master identity**:
An age identity file able to decrypt every shield in a repository. A YubiKey plugin identity stub, an SSH key, or a plain age key. Shields are encrypted to all master identities, so any one of them can open any shield.
_Avoid_: Key, recipient, pubkey

**Scope**:
Where a shield is attached. A shield is either flake-scoped or configuration-scoped.
_Avoid_: Level, kind, global, local

**Flake-scoped shield**:
A shield attached to the flake as a whole, readable before any configuration is evaluated.
_Avoid_: Global shield, global

**Configuration-scoped shield**:
A shield attached to one configuration (a NixOS system), readable only through that configuration's options.
_Avoid_: Local shield, local, host shield, node shield

**Configuration**:
An evaluated NixOS system that can own shields. The consumer decides which attribute set holds them.
_Avoid_: Host, node, machine

**Manifest**:
The flake's declared inventory of shields: master identities, flake-scoped shield files, and each configuration's shield files, with file locations relative to the flake root.
_Avoid_: Index, registry, catalogue

**Address**:
The name by which a shield is referred to on the command line: its name for a flake-scoped shield, `<configuration>:<name>` for a configuration-scoped one.
_Avoid_: Path, identifier, id

**Decrypt cache**:
The per-user directory holding decrypted shield contents so that an unlocked shield is not decrypted, and a hardware identity not prompted, again on every evaluation. Holds plaintext.
_Avoid_: Cache, tmp, temp files

**Wrapped nix**:
A Nix binary set whose configuration loads the shield builtin on every invocation, without exporting anything into the caller's environment.
_Avoid_: Plugin nix, devshell nix, patched nix
