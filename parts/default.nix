{
  # Only x86_64-linux is exercised by the checks; the rest are declared.
  systems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];

  imports = [
    ./checks.nix
    ./dev-shells.nix
    ./formatter.nix
    ./lib.nix
    ./packages.nix
  ];
}
