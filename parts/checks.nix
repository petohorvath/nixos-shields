{
  perSystem =
    { config, pkgs, ... }:
    {
      checks = {
        integration = pkgs.callPackage ../tests/integration/import-shield.nix {
          inherit (config.packages) nix;
          libDir = ../lib;
        };
        decrypt-cache = pkgs.callPackage ../tests/unit/decrypt-cache.nix { };
      };
    };
}
