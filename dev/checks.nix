{
  formatter,
  inputs,
  pkgs,
}:
let
  inherit (pkgs) lib;

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
lib.attrsets.unionOfDisjoint (import ../tests { inherit inputs pkgs; }) {
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
      shellcheck --shell bash packages/*/*.sh tests/build/*.sh
      actionlint .github/workflows/*.yml
    '';
  };
}
