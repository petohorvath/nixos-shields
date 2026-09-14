# The cache script: a store-path shebang, every tool on PATH from the store.
{
  writeShellApplication,
  coreutils,
  rage,
}:
writeShellApplication {
  name = "nixos-shields-decrypt";
  runtimeInputs = [
    coreutils
    rage
  ];
  text = builtins.readFile ./decrypt.sh;
}
