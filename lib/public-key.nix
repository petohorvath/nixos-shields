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
    isString
    stringLength
    substring
    ;

  prefixes = [
    "age1"
    "ssh-ed25519 "
    "ssh-rsa "
  ];

  hasPrefix = prefix: string: substring 0 (stringLength prefix) string == prefix;
in
{
  isPublicKey = value: isString value && any (prefix: hasPrefix prefix value) prefixes;

  notPublicKeyMessage = "is not a public key: it must start with age1, ssh-ed25519, or ssh-rsa";
}
