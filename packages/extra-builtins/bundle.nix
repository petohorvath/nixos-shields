/*
  The entry point of the extra-builtins bundle, copied into it as
  default.nix. nix-plugins admits the extra-builtins path and what lies
  below it, so in pure evaluation every file read here sits in the
  bundle: compose.nix, the kit's builtins as kit.nix, and a copy of each
  consumer entry as extras/<index>, whose names extras.json lists in
  order.
*/
args:
let
  names = builtins.fromJSON (builtins.readFile ./extras.json);

  extras = builtins.genList (index: {
    name = builtins.elemAt names index;
    builtins = import (./extras + "/${toString index}");
  }) (builtins.length names);
in
import ./compose.nix (import ./kit.nix) extras args
