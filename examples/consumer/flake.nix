/*
  A plain-flake consumer of nixos-shields: two NixOS configurations,
  each declaring one configuration-scoped shield built from `dir` by
  the consumer's own wiring. `alpha` decrypts `shields/alpha.nix.age`
  with the committed throwaway identity; `beta` declares a file that
  does not exist, so reading its values fails naming that file.
*/
{
  description = "Example consumer of nixos-shields";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-shields = {
      url = "github:petohorvath/nixos-shields";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, nixos-shields, ... }:
    let
      inherit (nixpkgs.lib) genAttrs nixosSystem;

      # Every configuration reads its shield from `<dir>/<name>.nix.age`.
      mkConfiguration =
        name:
        nixosSystem {
          modules = [
            nixos-shields.nixosModules.default
            (
              { config, ... }:
              {
                age.shields = {
                  masterIdentities = [ ./master-identities/throwaway.txt ];
                  dir = ./shields;
                  files.facts = config.age.shields.dir + "/${name}.nix.age";
                };

                # A shield value is ordinary configuration once decrypted.
                networking.hostName = name;
                networking.domain = config.age.shields.values.facts.domain;

                nixpkgs.hostPlatform = "x86_64-linux";
                system.stateVersion = "25.11";
              }
            )
          ];
        };
    in
    {
      nixosConfigurations = genAttrs [ "alpha" "beta" ] mkConfiguration;
    };
}
