# test-standard v1: copied from the test-standard skill; do not edit here.
# Turn the build entry point's tests into checks named build-<test>. A
# test that returns an attrset of derivations becomes a linkFarm of its
# cases, which declares the system features they require.
{ pkgs, repo }:
tests:
let
  inherit (pkgs) lib;

  # The derivations of an attrset of cases, with nested attribute paths
  # joined by / into link names.
  linksIn =
    prefix: cases:
    lib.concatLists (
      lib.mapAttrsToList (
        caseName: case:
        let
          linkName = prefix + caseName;
        in
        if lib.isDerivation case then
          [
            {
              name = linkName;
              path = case;
            }
          ]
        else
          linksIn "${linkName}/" case
      ) cases
    );

  combineCases =
    testName: cases:
    let
      links = linksIn "" cases;
      requiredSystemFeatures = lib.unique (
        lib.concatMap (link: link.path.requiredSystemFeatures or [ ]) links
      );
      linkFarm = pkgs.linkFarm "${repo}-build-${testName}" links;
    in
    if links == [ ] then
      throw "build test ${testName} has no cases"
    else if requiredSystemFeatures == [ ] then
      linkFarm
    else
      linkFarm.overrideAttrs { inherit requiredSystemFeatures; };
in
lib.mapAttrs' (
  testName: test:
  lib.nameValuePair "build-${testName}" (
    if lib.isDerivation test then test else combineCases testName test
  )
) tests
