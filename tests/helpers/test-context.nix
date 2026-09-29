{ flakeParts, nixpkgs }:
let
  inherit (nixpkgs) lib;
  # A consumer's flake root. Only its path is read; it need not exist.
  flakeRoot = /example/flake;
  shields = import ./flake-outputs.nix { inherit flakeParts nixpkgs; };
  evaluation = import ./evaluate.nix {
    inherit
      flakeParts
      flakeRoot
      lib
      shields
      ;
  };
in
evaluation
// {
  inherit flakeRoot lib;
  shieldsLib = shields.lib;
  # The example's shield exists, so reading it gets past the file check.
  existingShieldPath = ../../examples/consumer/shields/alpha.nix.age;
}
