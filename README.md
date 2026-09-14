# nixos-shields

Evaluation-time encrypted Nix expressions. A shield keeps identifying configuration values (domain names, real usernames, MAC addresses, disk serials) out of a public git repository while Nix can still read them during evaluation.

## Security boundary

A shield is not a secret. Its decrypted values land in the Nix store of every machine that evaluates or deploys the configuration, and in the per-user decrypt cache on disk. Anything that must stay confidential after deployment (passwords, tokens, private keys) belongs in a runtime secret manager such as agenix or sops-nix, never in a shield.

## Shields

A shield is a Nix expression stored age-encrypted in git and decrypted when Nix evaluates it. Its file name ends in `.nix.age`. It is encrypted to every master identity of the repository (a YubiKey plugin identity, an SSH key, or a plain age key), so any one of them can open it. `CONTEXT.md` holds the full glossary; `docs/adr/0001` records why decryption happens at evaluation time.

## Supported Nix version

The shield builtin is provided by [nix-plugins](https://github.com/shlevy/nix-plugins), which must be compiled against the exact Nix that loads it. The kit builds it against the Nix 2.34 series from nixpkgs (`nixVersions.nix_2_34`). A compatibility patch, `packages/nix-plugins/nix-2.34.patch`, is carried in-kit until an upstream nix-plugins release builds against that Nix. A newer Nix or a newer nix-plugins may make the patch unnecessary, or need new hunks.

Only x86_64-linux is exercised by the checks; outputs are declared for aarch64-linux and aarch64-darwin as well. x86_64-darwin is not declared, as nixpkgs dropped it in 26.11.

## Wrapped Nix

`lib.mkNix` returns a Nix binary set whose every invocation loads the builtin. Each binary is wrapped individually with `NIX_CONFIG` set for that process only and argv[0] preserved, so `nix-store`, `nix-build` and friends keep their multi-call behaviour and nothing is exported into the caller's shell.

```nix
nixos-shields.lib.mkNix {
  inherit pkgs;
  nix = pkgs.nixVersions.nix_2_34; # default; a concrete series, never pkgs.nix
  extraConfig = "accept-flake-config = true"; # the kit sets no such policy itself
  extraBuiltinsFile = nixos-shields.lib.mkExtraBuiltinsFile { inherit pkgs; }; # default
}
```

A ready-made set with defaults:

```sh
nix shell github:petohorvath/nixos-shields#nix
```

## Importing a shield

`lib.importShield` takes the master identity list and the shield file and returns the decrypted value. It fails with a message naming the file when the file does not exist, and with an explicit message when the identity list is empty.

```nix
nixos-shields.lib.importShield [ ./master-ids/yubikey-1.pub ] ./shields/beta.nix.age
```

Decrypted plaintext is cached per user under `/var/tmp/nixos-shields-<uid>`, keyed by the file's content hash; `NIXOS_SHIELDS_CACHE_DIR` overrides the location.

## Checks

```sh
nix flake check
```

The integration check runs the wrapped Nix inside the build sandbox against a fixture encrypted to a throwaway key generated at check time, and doubles as the ABI canary: it rebuilds whenever the Nix or the plugin changes.
