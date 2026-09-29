/*
  A flake-parts consumer with a flake-scoped shield shared by two
  configurations. Each configuration declares its own shield using
  the directory and identities from the pre-configured NixOS module.
  `beta`'s shield file is deliberately missing.
*/
{
  description = "Example consumer of nixos-shields";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    nixos-shields = {
      url = "github:petohorvath/nixos-shields";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      nixos-shields,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { config, ... }:
      let
        inherit (nixpkgs.lib) genAttrs nixosSystem;
        shared = config.shields.values.shared;

        # Every configuration reads its shield from `<dir>/<name>.nix.age`.
        mkConfiguration =
          name:
          nixosSystem {
            modules = [
              config.shields.nixosModule
              (
                { config, ... }:
                {
                  age.shields.files.facts = config.age.shields.dir + "/${name}.nix.age";

                  # Both scopes supply ordinary configuration once decrypted.
                  networking = {
                    hostName = name;
                    domain = config.age.shields.values.facts.domain;
                    search = [ shared.domain ];
                  };

                  nixpkgs.hostPlatform = "x86_64-linux";
                  system.stateVersion = "25.11";
                }
              )
            ];
          };
      in
      {
        imports = [ nixos-shields.flakeModules.default ];
        systems = [ ];

        shields = {
          dir = ./shields;
          masterIdentities = [ ./master-identities/throwaway.txt ];
          files.shared = ./shields/shared.nix.age;
        };

        # This value is readable before either configuration evaluates.
        flake.sharedShield = shared;
        flake.nixosConfigurations = genAttrs [ "alpha" "beta" ] mkConfiguration;
      }
    );
}
