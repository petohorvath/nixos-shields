{ inputs, ... }:
{
  imports = [ "${inputs.git-hooks}/flake-module.nix" ];

  perSystem =
    { config, ... }:
    {
      pre-commit.settings.hooks = {
        treefmt = {
          enable = true;
          package = config.formatter;
          stages = [ "pre-commit" ];
        };

        # This stage is excluded from checks.pre-commit, avoiding recursion.
        flake-check = {
          enable = true;
          name = "nix flake check";
          entry = "${config.packages.nix}/bin/nix flake check --print-build-logs";
          pass_filenames = false;
          always_run = true;
          stages = [ "pre-push" ];
        };
      };
    };
}
