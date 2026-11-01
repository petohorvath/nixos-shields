/*
  The public-key rule: a public key is a string starting with `age1`,
  which covers age plugin keys such as `age1yubikey1…`, `ssh-ed25519 `,
  or `ssh-rsa `, the key types rage encrypts to. Nothing after the
  prefix is parsed, so a key ending in a newline, as agenix-rekey
  produces when it reads a public key file, passes.

  Exports:
    isPublicKey: whether a value satisfies the rule.
    notPublicKeyMessage: the end of the message for a value that does
      not, to follow the words naming it.
*/
let
  inherit (builtins)
    any
    concatStringsSep
    elemAt
    genList
    isString
    length
    replaceStrings
    stringLength
    substring
    ;

  prefixes = [
    "age1"
    "ssh-ed25519 "
    "ssh-rsa "
  ];

  hasPrefix = prefix: string: substring 0 (stringLength prefix) string == prefix;

  # The prefixes as the message lists them, without the space that ends
  # an SSH key type: "age1, ssh-ed25519, or ssh-rsa".
  listedPrefixes =
    let
      names = map (prefix: replaceStrings [ " " ] [ "" ] prefix) prefixes;
      lastIndex = length names - 1;
    in
    "${concatStringsSep ", " (genList (elemAt names) lastIndex)}, or ${elemAt names lastIndex}";
in
{
  isPublicKey = value: isString value && any (prefix: hasPrefix prefix value) prefixes;

  notPublicKeyMessage = "is not a public key: it must start with ${listedPrefixes}";
}
