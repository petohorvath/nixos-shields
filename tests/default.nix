{
  formatter,
  inputs,
  packages,
  pkgs,
}:
let
  inherit (pkgs) lib;

  # The kit as the example's input: its flake and code, not its docs,
  # so a README edit does not rebuild the integration check.
  kit = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../flake.nix
      ../flake-module.nix
      ../lib
      ../nixos
      ../packages
    ];
  };

  sourceDir = lib.cleanSource ../.;

  # Run a script against a writable copy of the source.
  runSourceCheck =
    {
      name,
      tools,
      script,
    }:
    pkgs.runCommand name { nativeBuildInputs = tools; } ''
      cp -R ${sourceDir} source
      chmod -R u+w source
      cd source
      ${script}
      touch "$out"
    '';
in
{
  tests = pkgs.callPackage ./checks.nix {
    inherit (inputs) nixpkgs;
    flakeParts = inputs.flake-parts;
  };
  decrypt-cache = pkgs.callPackage ./integration/decrypt-cache.nix { };
  cli = pkgs.callPackage ./integration/cli.nix {
    inherit (inputs) nixpkgs;
    inherit kit;
    inherit (packages) nix nixos-shields;
    flakeParts = inputs.flake-parts;
    example = ../examples/consumer;
  };
  integration = pkgs.callPackage ./integration/wrapped-nix.nix {
    inherit (inputs) nixpkgs;
    inherit kit;
    inherit (packages) nix;
    flakeParts = inputs.flake-parts;
    libDir = ../lib;
    example = ../examples/consumer;
    composedNix = (import ../lib).mkNix {
      inherit pkgs;
      extraBuiltinsFile = pkgs.writeText "consumer-extra-builtins.nix" ''
        args:
        (import ${packages.nix.extraBuiltinsFile} args) // {
          consumerAnswer = 42;
        }
      '';
    };
  };
  formatting = runSourceCheck {
    name = "nixos-shields-formatting";
    tools = [ formatter ];
    script = "treefmt --ci --tree-root .";
  };
  lint = runSourceCheck {
    name = "nixos-shields-lint";
    tools = [
      pkgs.actionlint
      pkgs.deadnix
      pkgs.shellcheck
      pkgs.statix
    ];
    script = ''
      statix check .
      deadnix --fail .
      shellcheck --shell bash packages/*/*.sh tests/integration/*.sh
      actionlint .github/workflows/*.yml
    '';
  };
}
