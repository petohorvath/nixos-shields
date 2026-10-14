/*
  A flake-parts consumer with two configurations that share one shield
  file. A module common to both declares the shield directory and the
  master identity. `beta`'s own shield file is deliberately missing, and
  `deploy` reads `alpha`'s shield value from outside the configuration.
*/
{
  description = "Example consumer of nixos-shields";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
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
        inherit (nixpkgs.lib) genAttrs mapAttrs nixosSystem;

        # Settings every configuration shares, as with agenix-rekey's
        # age.rekey.masterIdentities.
        commonModule = {
          imports = [ nixos-shields.nixosModules.default ];
          age.shields = {
            dir = ./shields;
            masterIdentities = [ ./master-identities/throwaway.txt ];
          };
        };

        # Every configuration reads its own shield from
        # `<dir>/<name>.nix.age` and the shared one from
        # `<dir>/shared.nix.age`.
        mkConfiguration =
          name:
          nixosSystem {
            modules = [
              commonModule
              (
                { config, ... }:
                {
                  age.shields.files = {
                    facts = config.age.shields.dir + "/${name}.nix.age";
                    shared = config.age.shields.dir + "/shared.nix.age";
                  };

                  # Both shields supply ordinary configuration once
                  # decrypted.
                  networking = {
                    hostName = name;
                    domain = config.age.shields.values.facts.domain;
                    search = [ config.age.shields.values.shared.domain ];
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

        flake.nixosConfigurations = genAttrs [ "alpha" "beta" ] mkConfiguration;

        # A configuration's shield values are readable from outside it,
        # here in the shape deploy-rs reads its targets from.
        flake.deploy.nodes = mapAttrs (_: configuration: {
          hostname = configuration.config.age.shields.values.facts.domain;
        }) config.flake.nixosConfigurations;
      }
    );
}
