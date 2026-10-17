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
An age identity file able to decrypt every shield in a repository: a YubiKey plugin identity stub, an SSH key, or a plain age key. Each configuration declares its own, and every shield is encrypted to those of all configurations combined, so any one of them can open any shield. It lies inside the flake root, committed with the shields, or outside it, such as under the home directory. A plain private key belongs outside, where it is never committed or copied into the Nix store.
_Avoid_: Key, recipient, pubkey

**Extra encryption pubkey**:
A public key, or a recipients file of public keys, that every shield is encrypted to but that is never used to decrypt, such as an offline backup key or a team's keys. Unlike a master identity, it has no identity file in the flake, so evaluation and editing never try it; its private key opens shields only outside the kit, such as after losing every master identity.
_Avoid_: Backup identity, extra recipient, master identity

**Primary identity**:
The identity file that the person at the keyboard holds, chosen by them rather than declared in the flake, and tried before the master identities when a shield is decrypted, or instead of them. It spares prompts for hardware keys they do not hold. It need not be a master identity, but it opens shields only if one of them, or an extra encryption pubkey, matches its key.
_Avoid_: Default identity, preferred key, first master identity

**Configuration**:
An evaluated NixOS system that can own shields. The consumer decides which attribute set holds them.
_Avoid_: Host, node, machine

**Manifest**:
The flake's declared inventory of shields: the master identities and extra encryption pubkeys of all configurations combined and each configuration's shield files, with file locations relative to the flake root.
_Avoid_: Index, registry, catalogue

**Address**:
The name by which a shield is referred to on the command line: `<configuration>:<name>`. A shield file declared by several configurations has one address in each.
_Avoid_: Path, identifier, id

**Decrypt cache**:
The per-user directory holding decrypted shield contents so that an unlocked shield is not decrypted, and a hardware identity not prompted, again on every evaluation or edit. Evaluation and the command-line tool both read shields through it. Holds plaintext.
_Avoid_: Cache, tmp, temp files

**Wrapped nix**:
A Nix binary set whose configuration loads the shield builtin on every invocation, without exporting anything into the caller's environment.
_Avoid_: Plugin nix, devshell nix, patched nix
