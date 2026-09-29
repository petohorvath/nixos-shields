{
  formatter,
  inputs,
  packages,
  pkgs,
}:
import ../tests {
  inherit
    formatter
    inputs
    packages
    pkgs
    ;
}
