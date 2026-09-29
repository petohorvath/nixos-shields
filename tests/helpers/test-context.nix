{ flakeParts, nixpkgs }:
let
  inherit (nixpkgs) lib;
  shields = import ./flake-outputs.nix { inherit flakeParts nixpkgs; };
  evaluation = import ./evaluate.nix { inherit flakeParts lib shields; };
in
evaluation
// {
  inherit lib;
  shieldsLib = shields.lib;
  # The example's shield exists, so reading it gets past the file check.
  existingShieldPath = ../../examples/consumer/shields/alpha.nix.age;
}
