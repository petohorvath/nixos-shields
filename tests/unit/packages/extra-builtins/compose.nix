# The builtins the wrapped Nix loads: the kit's merged with a consumer's
# entries, each applied to the arguments nix-plugins supplies, and the
# failures for a name the kit reserves or two entries share.
{ internal, ... }:
let
  inherit (internal) composeBuiltins extraBuiltins;

  # The arguments nix-plugins supplies, with an exec that returns its
  # argv instead of running it.
  args = {
    exec = argv: argv;
    importNative = _: _: null;
  };

  compose = extras: composeBuiltins extraBuiltins extras args;
in
{
  testKitAloneDefinesImportShield = {
    expr = builtins.attrNames (compose [ ]);
    expected = [ "importShield" ];
  };

  # Each entry receives exec, so a consumer's builtin can run a program.
  testMergesEntriesAppliedToArgs = {
    expr =
      let
        builtins' = compose [
          {
            name = "answer.nix";
            builtins = _: { answer = 42; };
          }
          {
            name = "hostname.nix";
            builtins = { exec, ... }: { hostname = exec [ "hostname" ]; };
          }
        ];
      in
      {
        names = builtins.attrNames builtins';
        inherit (builtins') answer hostname;
      };
    expected = {
      names = [
        "answer"
        "hostname"
        "importShield"
      ];
      answer = 42;
      hostname = [ "hostname" ];
    };
  };

  # Forcing the merged set fails, so an entry cannot replace the kit's
  # builtin unnoticed.
  testRejectsEntryDefiningKitBuiltin = {
    expr = builtins.attrNames (compose [
      {
        name = "shadow.nix";
        builtins = _: { importShield = null; };
      }
    ]);
    expectedError = {
      type = "ThrownError";
      msg = "nixos-shields: extra builtins shadow\\.nix define importShield, which the kit reserves";
    };
  };

  testRejectsEntriesDefiningOneName = {
    expr = builtins.attrNames (compose [
      {
        name = "first.nix";
        builtins = _: { answer = 41; };
      }
      {
        name = "unrelated.nix";
        builtins = _: { other = 0; };
      }
      {
        name = "second.nix";
        builtins = _: { answer = 42; };
      }
    ]);
    expectedError = {
      type = "ThrownError";
      msg = "nixos-shields: extra builtins first\\.nix and second\\.nix both define answer";
    };
  };
}
