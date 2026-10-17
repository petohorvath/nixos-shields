{
  git,
  mkShellNoCC,
  nil,
  nix-unit,
  packages,
  rage,
  statix,
  treefmtShell,
}:
mkShellNoCC {
  inputsFrom = [ treefmtShell ];
  # The wrapped Nix, so `nix flake check` here loads the builtin too.
  packages = [
    packages.nix
    git
    nil
    nix-unit
    statix
    rage
  ];
}
