/*
  Coerces a master identity entry to the attribute set form of
  agenix-rekey's age.rekey.masterIdentities entries. A path or a string
  names the identity file alone; an attribute set keeps its `identity`
  and its `pubkey`, null when absent.
*/
entry:
if builtins.isAttrs entry then
  {
    inherit (entry) identity;
    pubkey = entry.pubkey or null;
  }
else
  {
    identity = entry;
    pubkey = null;
  }
