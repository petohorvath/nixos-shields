{
  inputs,
  packages,
  pkgs,
}:
let
  inherit (pkgs) lib;

  # Every package consumers install, so CI builds it.
  packageChecks = lib.mapAttrs' (name: lib.nameValuePair "package-${name}") (
    removeAttrs packages [ "default" ]
  );
in
lib.foldl' lib.attrsets.unionOfDisjoint { } [
  (import ../tests { inherit inputs pkgs; })
  packageChecks
  {
    lint = pkgs.runCommand "nixos-shields-lint" { nativeBuildInputs = [ pkgs.statix ]; } ''
      cd ${../.}
      statix check .
      touch "$out"
    '';
  }
]
