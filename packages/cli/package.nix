{
  writeShellApplication,
  bash,
  coreutils,
  decrypt,
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
    decrypt
    diffutils
    gnugrep
    jq
    nix
    rage
  ];
  text = builtins.readFile ./nixos-shields.sh;
}
