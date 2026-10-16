# The flake exposes the code that the other suites import from source.
{
  helpers,
  pkgs,
  shieldsLib,
  ...
}:
let
  inherit (helpers) flakeOutputs;

  drvPaths = builtins.mapAttrs (_: package: package.drvPath);

  # The files a module imports, through the wrappers flake-parts adds.
  importedFiles =
    module:
    if builtins.isPath module then
      [ module ]
    else
      builtins.concatMap importedFiles (module.imports or [ ]);
in
{
  # Functions do not compare equal, so only the names are checked.
  testLib = {
    expr = builtins.attrNames flakeOutputs.lib;
    expected = builtins.attrNames shieldsLib;
  };

  testNixosModule = {
    expr = importedFiles flakeOutputs.nixosModules.default;
    expected = [ ../../nixos/module.nix ];
  };

  testFlakeModule = {
    expr = importedFiles flakeOutputs.flakeModules.default;
    expected = [ ../../flake-module.nix ];
  };

  testPackages = {
    expr = drvPaths flakeOutputs.packages.${pkgs.stdenv.hostPlatform.system};
    expected = drvPaths (import ../../packages pkgs);
  };
}
