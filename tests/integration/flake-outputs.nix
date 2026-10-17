# The flake exposes the code that the other suites import from source.
{ self, shieldsLib, ... }:
let
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
    expr = builtins.attrNames self.lib;
    expected = builtins.attrNames shieldsLib;
  };

  testNixosModule = {
    expr = importedFiles self.nixosModules.default;
    expected = [ ../../nixos/module.nix ];
  };

  testFlakeModule = {
    expr = importedFiles self.flakeModules.default;
    expected = [ ../../flake-module.nix ];
  };
}
