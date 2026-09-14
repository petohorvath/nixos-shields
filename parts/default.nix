{
  /*
    Only x86_64-linux is exercised by the checks; the rest are declared.
    x86_64-darwin is absent because nixpkgs dropped it in 26.11.
  */
  systems = [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
  ];

  imports = [
    ./checks.nix
    ./dev-shells.nix
    ./formatter.nix
    ./lib.nix
    ./modules.nix
    ./packages.nix
  ];
}
