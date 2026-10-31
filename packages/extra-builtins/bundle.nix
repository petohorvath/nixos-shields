/*
  The entry point of the extra-builtins bundle, copied into it as
  default.nix. nix-plugins admits the extra-builtins path and what lies
  below it, so in pure evaluation every file read here sits in the
  bundle: compose.nix, the kit's builtins as kit.nix, and a copy of each
  consumer entry, which extras.json lists in order as { name, file }.
*/
args:
let
  extras = map (extra: {
    inherit (extra) name;
    builtins = import (./. + "/${extra.file}");
  }) (builtins.fromJSON (builtins.readFile ./extras.json));
in
import ./compose.nix (import ./kit.nix) extras args
