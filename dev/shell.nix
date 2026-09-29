{
  actionlint,
  deadnix,
  formatter,
  git,
  mkShellNoCC,
  nil,
  nix-unit,
  packages,
  rage,
  shellcheck,
  statix,
}:
mkShellNoCC {
  # The wrapped Nix, so `nix flake check` here loads the builtin too.
  packages = [
    packages.nix
    git
    nil
    nix-unit
    formatter
    statix
    deadnix
    shellcheck
    actionlint
    rage
  ];
}
