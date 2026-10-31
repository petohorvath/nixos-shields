# lib.mkNix's checks on the consumer's extra builtins, which fail before
# the bundle holding them is built.
{ pkgs, shieldsLib, ... }:
let
  extraBuiltinsDirWith =
    extraBuiltins: (shieldsLib.mkNix { inherit pkgs extraBuiltins; }).extraBuiltinsDir;
in
{
  # A plain string names no store path, so the bundle could not track
  # the file's content.
  testRejectsStringEntry = {
    expr = (extraBuiltinsDirWith [ "/srv/builtins/answer.nix" ]).name;
    expectedError = {
      type = "ThrownError";
      msg = "nixos-shields: extra builtins entry /srv/builtins/answer\\.nix must be a path or a derivation";
    };
  };
  testRejectsEntryNotInList = {
    expr = (extraBuiltinsDirWith (pkgs.writeText "answer.nix" "_: { }")).name;
    expectedError = {
      type = "ThrownError";
      msg = "nixos-shields: extraBuiltins must be a list of paths or derivations";
    };
  };
}
