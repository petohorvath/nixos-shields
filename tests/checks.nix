# Run the nix-unit suites in the build sandbox with the flake's inputs.
{
  flakeParts,
  lib,
  nix-unit,
  nixpkgs,
  runCommand,
}:
let
  sourceDir = lib.cleanSource ../.;

  # Reconstruct inputs from store paths so the sandbox fetches no flakes.
  evaluationInputsPath = builtins.toFile "nixos-shields-test-inputs.nix" ''
    import ${sourceDir}/tests/helpers/evaluation-inputs.nix {
      flakePartsDir = "${flakeParts}";
      nixpkgsDir = "${nixpkgs}";
    }
  '';
in
runCommand "nixos-shields-tests" { nativeBuildInputs = [ nix-unit ]; } ''
  # The writable evaluation store lets evaluation add paths in the sandbox.
  nix-unit --show-trace \
    --eval-store "$TMPDIR/eval-store" --gc-roots-dir "$TMPDIR/gc-roots" \
    ${sourceDir}/tests/entrypoint.nix \
    --arg nixpkgs '(import ${evaluationInputsPath}).nixpkgs' \
    --arg flakeParts '(import ${evaluationInputsPath}).flakeParts'
  touch "$out"
''
