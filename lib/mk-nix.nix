/*
  mkNix — builds the wrapped Nix: a Nix binary set whose every
  invocation loads the shield builtin. Each binary is wrapped to set
  NIX_CONFIG for that process only, with argv[0] preserved so
  nix-store, nix-build and friends keep their multi-call behaviour;
  nothing is exported into the caller's shell.

  Inputs:
    pkgs: the package set to build with.
    nix: the Nix package to wrap; defaults to Nix 2.34, the series the
      plugin patch supports.
    extraConfig: extra nix.conf lines, such as accept-flake-config; the
      kit sets no such policy. Defaults to "".
    extraBuiltins: the consumer's own builtins, each a path or a
      derivation holding an extra-builtins function, as a file or as a
      directory with a default.nix. They are merged with the kit's
      importShield; a name the kit or an earlier entry defines fails.
      Defaults to [ ].

  Returns a derivation with the wrapped binaries; its passthru holds
  extraBuiltinsDir, the directory loaded as the extra-builtins file,
  nix, and the plugins it loads.

  Example:
    nixos-shields.lib.mkNix {
      inherit pkgs;
      extraConfig = "accept-flake-config = true";
      extraBuiltins = [ ./nix/extra-builtins.nix ];
    }
*/
{
  pkgs,
  # A concrete series, never pkgs.nix: the plugin must match its ABI.
  nix ? pkgs.nixVersions.nix_2_34,
  extraConfig ? "",
  extraBuiltins ? [ ],
}:
let
  inherit (pkgs.lib) escapeShellArg;

  plugins = pkgs.callPackage ../packages/nix-plugins/package.nix { inherit nix; };

  extraBuiltinsDir = pkgs.callPackage ../packages/extra-builtins/package.nix {
    decrypt = pkgs.callPackage ../packages/decrypt/package.nix { };
    inherit extraBuiltins;
  };

  nixConfig = ''
    plugin-files = ${plugins}/lib/nix/plugins
    extra-builtins-file = ${extraBuiltinsDir}
    ${extraConfig}
  '';
in
pkgs.symlinkJoin {
  name = "nixos-shields-nix-${nix.version}";
  paths = [ nix ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  /*
    Wrap the original binary, not the symlink in $out: iterating in
    lexical order wraps $out/bin/nix first, and a later symlink such as
    nix-store -> nix would otherwise resolve to that fresh wrapper and
    lose its argv[0] on the inner exec.
  */
  postBuild = ''
    for bin in "$out"/bin/*; do
      name=$(basename "$bin")
      rm "$bin"
      makeWrapper "${nix}/bin/$name" "$bin" \
        --argv0 "$name" \
        --set NIX_CONFIG ${escapeShellArg nixConfig}
    done
  '';
  passthru = { inherit extraBuiltinsDir nix plugins; };
  meta = {
    inherit (nix.meta) description license;
    mainProgram = "nix";
  };
}
