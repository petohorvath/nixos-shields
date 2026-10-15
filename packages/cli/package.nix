{
  writeShellApplication,
  bash,
  coreutils,
  diffutils,
  jq,
  nix,
  rage,
}:
writeShellApplication {
  name = "nixos-shields";
  runtimeInputs = [
    bash
    coreutils
    diffutils
    jq
    nix
    rage
  ];
  text = builtins.readFile ./nixos-shields.sh;
}
