/*
  Reads the public key from a YubiKey or FIDO2 identity stub, following
  agenix-rekey's rules: the file holds exactly one line starting with
  `AGE-`, the plugin's identity line, and exactly one key in the
  plugin's comments. Returns null for any other file, including a
  missing one, so encryption falls back to presenting the identity file
  and never guesses.
*/
path:
let
  inherit (builtins)
    concatMap
    filter
    head
    isList
    isString
    length
    match
    pathExists
    readFile
    split
    ;

  # Each plugin's identity line prefix, the comment introducing its
  # public key, and the key itself.
  stubKinds = [
    {
      identityPrefix = "AGE-PLUGIN-YUBIKEY-";
      comment = "Recipient: age1yubikey1";
      key = "age1yubikey1[0-9a-z]+";
    }
    {
      identityPrefix = "AGE-PLUGIN-FIDO2-HMAC-";
      comment = "public key: age1";
      key = "age1[0-9a-z]+";
    }
  ];

  lines = filter isString (split "\n" (readFile path));
  hasPrefix = prefix: line: match "${prefix}.*" line != null;
  ageLines = filter (hasPrefix "AGE-") lines;

  # Every key in lines containing the kind's comment, repeats included,
  # as agenix-rekey's grep counts them.
  keysOf =
    { comment, key, ... }:
    concatMap (line: map head (filter isList (split "(${key})" line))) (
      filter (line: match ".*${comment}.*" line != null) lines
    );

  matchingKinds = filter (kind: hasPrefix kind.identityPrefix (head ageLines)) stubKinds;
  keys = keysOf (head matchingKinds);
in
if !pathExists path || length ageLines != 1 || matchingKinds == [ ] || length keys != 1 then
  null
else
  head keys
