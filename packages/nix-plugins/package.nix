/*
  nix-plugins built against the same Nix the wrapped binary set runs, so
  the plugin's ABI matches. nixpkgs pins it to an older Nix; the patch
  carries the fixes until an upstream release catches up.
*/
{ nix-plugins, nix }:
let
  # Since Nix 2.0 one package bundles every component the build links.
  components = {
    nix-cmd = nix;
    nix-expr = nix;
    nix-main = nix;
    nix-store = nix;
  };
in
(nix-plugins.override { nixComponents = components; }).overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./nix-2.34.patch ];
})
