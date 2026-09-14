{
  writeShellApplication,
  bash,
  coreutils,
  jq,
  nix,
  rage,
}:
writeShellApplication {
  name = "nixos-shields";
  runtimeInputs = [
    bash
    coreutils
    jq
    nix
    rage
  ];
  text = builtins.readFile ./nixos-shields.sh;
}
