#!/usr/bin/env bash

valid_username() {
  local name=$1
  [[ $name =~ ^app_[a-z0-9_]{1,26}$ ]]
}

valid_password() {
  local password=$1
  [[ $password =~ ^[A-Za-z0-9_+!-]{16,30}$ &&
     $password =~ [A-Z] && $password =~ [a-z] &&
     $password =~ [0-9] && $password =~ [_+!-] ]]
}

secret() {
  cat "/run/secrets/$1"
}

# The ACL file contains only hashes. Redis treats the leading # as an ACL rule.
redis_hash() {
  local hash
  hash=$(printf '%s' "$1" | sha256sum) || return
  printf '%s' "${hash%% *}"
}
