# nix-plugins built against the same Nix the wrapped binary set runs, so
# the plugin's ABI matches. Older nixpkgs pins it to an older Nix; the
# patch carries the fixes until an upstream release catches up.
{ nix-plugins, nix }:
let
  # Since Nix 2.0 one package bundles every component the build links.
  components = {
    nix-cmd = nix;
    nix-expr = nix;
    nix-main = nix;
    nix-store = nix;
  };

  # The patch is written against this release.
  patchedVersion = "16.0.1";
in
assert
  nix-plugins.version == patchedVersion
  || throw "nixos-shields: nix-plugins ${nix-plugins.version} is not ${patchedVersion}; check whether packages/nix-plugins/nix-2.34.patch is still needed";
(nix-plugins.override { nixComponents = components; }).overrideAttrs {
  # Newer nixpkgs carries the same upstream fixes as patches of its own,
  # which the backport would conflict with. Replacing them builds the
  # same source under every nixpkgs.
  patches = [ ./nix-2.34.patch ];
}
