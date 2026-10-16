# test-standard v1: copied from the test-standard skill; do not edit here.
/*
  Turn a nix-unit entry point into a check, so its suites run under
  `nix flake check` and the project policy's `test`. Each input that the
  entry point declares comes from the flake's inputs as a tree of store
  paths, which helpers/evaluation-inputs.nix rebuilds in the sandbox, so
  the build fetches nothing and input overrides reach every suite.
*/
{
  inputs,
  pkgs,
  repo,
  srcDir,
}:
{
  kind,
  name ? kind,
  suites ? null,
  extraArgs ? { },
  requiredSystemFeatures ? [ ],
  postCheck ? "",
  jobs ? null,
}:
let
  inherit (pkgs) lib;

  entryPoint = "${srcDir}/tests/${kind}";
  evaluationInputsPath = "${srcDir}/tests/helpers/evaluation-inputs.nix";

  # An input as a Nix expression of its store paths, keeping every
  # transitive input. Interpolating each path makes it a build input.
  inputTree =
    input:
    let
      path = builtins.toJSON "${input}";
      subInputs = lib.concatMapAttrsStringSep " " (
        inputName: subInput: "${builtins.toJSON inputName} = ${inputTree subInput};"
      ) input.inputs;
    in
    if input._type or null == "flake" then
      "{ path = ${path}; inputs = { ${subInputs} }; }"
    else
      "{ path = ${path}; flake = false; }";

  # The declared arguments that a flake input supplies; extraArgs and
  # system are passed separately.
  inputArgs = lib.filterAttrs (
    argName: _: argName != "system" && !(extraArgs ? ${argName}) && inputs ? ${argName}
  ) (builtins.functionArgs (import entryPoint));

  argExpressions =
    lib.mapAttrs (
      argName: _: "(import ${evaluationInputsPath}) ${inputTree inputs.${argName}}"
    ) inputArgs
    // extraArgs;

  nixArgs =
    lib.concatLists (
      lib.mapAttrsToList (argName: expression: [
        "--arg"
        argName
        expression
      ]) argExpressions
    )
    ++ [
      "--argstr"
      "system"
      pkgs.stdenv.hostPlatform.system
    ];

  # Prints the attribute path of each group, an attrset that directly
  # holds test attributes, one per line.
  listGroupsPath = builtins.toFile "list-groups.nix" ''
    suites: tests:
    let
      selected =
        if suites == null then
          tests
        else
          builtins.listToAttrs (
            map (name: {
              inherit name;
              value = builtins.getAttr name tests;
            }) suites
          );
      isGroup =
        set:
        builtins.any (name: builtins.substring 0 4 name == "test") (
          builtins.attrNames set
        );
      groupsIn =
        prefix: set:
        builtins.concatMap (
          name:
          let
            value = builtins.getAttr name set;
            path = prefix ++ [ name ];
          in
          if !builtins.isAttrs value then
            [ ]
          else if isGroup value then
            [ (builtins.concatStringsSep "." path) ]
          else
            groupsIn path value
        ) (builtins.attrNames set);
    in
    builtins.concatStringsSep "\n" (groupsIn [ ] selected)
  '';

  suitesExpression =
    if suites == null then "null" else "[ ${lib.concatMapStringsSep " " builtins.toJSON suites} ]";

  # The entry point called as nix-unit calls it with nixArgs.
  entryPointExpression =
    let
      args = argExpressions // {
        system = builtins.toJSON pkgs.stdenv.hostPlatform.system;
      };
      bindings = lib.concatMapAttrsStringSep " " (
        argName: expression: "${builtins.toJSON argName} = (${expression});"
      ) args;
    in
    "import ${entryPoint} { ${bindings} }";

  listGroupsExpression = "import ${listGroupsPath} ${suitesExpression} (${entryPointExpression})";

  parallelJobs = if jobs == null then "\"$NIX_BUILD_CORES\"" else toString jobs;

  # nix-unit releases before 2.35 need a directory for their GC roots.
  gcRootsFlag = lib.optionalString (lib.versionOlder pkgs.nix-unit.version "2.35") "--gc-roots-dir \"$TMPDIR/gc-roots/$1\"";
in
pkgs.runCommand "${repo}-${name}"
  {
    nativeBuildInputs = [
      pkgs.nix
      pkgs.nix-unit
    ];
    inherit requiredSystemFeatures;
  }
  ''
    export HOME=$TMPDIR/home
    # The writable evaluation store lets evaluation add derivations.
    export EVAL_STORE=$TMPDIR/eval-store
    mkdir -p "$HOME" "$TMPDIR/logs" "$TMPDIR/failed"

    groups=$(nix eval --raw --impure --show-trace \
      --extra-experimental-features nix-command \
      --store "$EVAL_STORE" \
      --expr ${lib.escapeShellArg listGroupsExpression})
    if [[ -z $groups ]]; then
      echo "no test groups in ${entryPoint}" >&2
      exit 1
    fi

    # One nix-unit process for each group bounds the memory of each.
    runGroup() {
      nix-unit --show-trace --eval-store "$EVAL_STORE" ${gcRootsFlag} \
        ${entryPoint} ${lib.escapeShellArgs nixArgs} --attr "$1" \
        > "$TMPDIR/logs/$1.log" 2>&1 \
        || touch "$TMPDIR/failed/$1"
    }
    export -f runGroup
    xargs -d '\n' -n 1 -P ${parallelJobs} \
      bash -c 'runGroup "$1"' runGroup <<< "$groups"

    while IFS= read -r group; do
      echo "== $group"
      cat "$TMPDIR/logs/$group.log"
    done <<< "$groups"
    failed=$(ls "$TMPDIR/failed")
    if [[ -n $failed ]]; then
      echo "failed groups: ''${failed//$'\n'/ }" >&2
      exit 1
    fi

    ${postCheck}
    touch "$out"
  ''
