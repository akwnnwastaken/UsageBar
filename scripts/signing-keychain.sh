#!/bin/bash
# Sourced by the signer and the hosted-runner regression test.

cleanup_signing_keychain() {
  local status=$?
  if [[ "$keychain_search_saved" == true ]]; then
    security list-keychains -d user -s ${original_keychains[@]+"${original_keychains[@]}"} >/dev/null ||
      { echo 'Could not restore the original user Keychain search list.' >&2; status=1; }
  fi
  if [[ -e "$keychain" ]]; then
    security delete-keychain "$keychain" >/dev/null ||
      { echo 'Could not delete the temporary signing Keychain.' >&2; status=1; }
  fi
  rm -rf "$scratch" || { echo 'Could not remove signing scratch files.' >&2; status=1; }
  exit "$status"
}

open_signing_keychain() {
  local list path
  keychain="$scratch/signing.keychain-db"
  keychain_search_saved=false
  original_keychains=()
  trap cleanup_signing_keychain EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  list=$(security list-keychains -d user) || die 'Could not read the user Keychain search list'
  if [[ -n "$list" ]]; then
    while IFS= read -r path; do
      [[ "$path" =~ ^[[:space:]]*\"([^\"]+)\"$ ]] || die 'Unexpected Keychain search list format'
      original_keychains+=("${BASH_REMATCH[1]}")
    done <<< "$list"
  fi
  keychain_search_saved=true

  keychain_password=$(openssl rand -hex 32) || die 'Could not generate a temporary Keychain password'
  security create-keychain -p "$keychain_password" "$keychain" || die 'Could not create the temporary signing Keychain'
  security set-keychain-settings -lut 7200 "$keychain" || die 'Could not set temporary Keychain timeout'
  security unlock-keychain -p "$keychain_password" "$keychain" || die 'Could not unlock the temporary signing Keychain'
  # codesign uses the search list for trust-chain discovery even with an explicit identity Keychain.
  security list-keychains -d user -s "$keychain" ${original_keychains[@]+"${original_keychains[@]}"} ||
    die 'Could not register the temporary signing Keychain in the user search list'
}

import_signing_identity() {
  security import "$1" -k "$keychain" -P "$2" -T "$3" >/dev/null ||
    die 'PKCS#12 import failed. Check the archive format and matching password.'
  rm -f "$1"
}

allow_keychain_signing() {
  security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null ||
    die 'Could not configure private-key access for the signing tools'
}
