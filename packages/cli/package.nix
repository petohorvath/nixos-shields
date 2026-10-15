{
  writeShellApplication,
  bash,
  coreutils,
  diffutils,
  gnugrep,
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
    gnugrep
    jq
    nix
    rage
  ];
  text = builtins.readFile ./nixos-shields.sh;
}
