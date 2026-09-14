{
  perSystem =
    { config, pkgs, ... }:
    {
      checks.integration = pkgs.callPackage ../tests/integration/import-shield.nix {
        inherit (config.packages) nix;
        libDir = ../lib;
      };
    };
}
