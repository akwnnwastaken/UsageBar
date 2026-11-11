#!/bin/bash
set +x
set -euo pipefail
die() { printf '%s\n' "$*" >&2; exit 1; }

cd "$(dirname "$0")/.."
source scripts/signing-keychain.sh
umask 077
fixture=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/signing-test.XXXXXXXX")
trap 'rm -rf "$fixture"' EXIT
before=$(security list-keychains -d user)
default_before=$(security default-keychain -d user)
label='UsageBar ephemeral CI signing test'
password=$(openssl rand -hex 16)
cat > "$fixture/cert.conf" <<CONF
[req]
distinguished_name = name
prompt = no
x509_extensions = signing
[name]
CN = $label
[signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
CONF
openssl req -new -x509 -newkey rsa:2048 -nodes -sha256 -days 1 -config "$fixture/cert.conf" \
  -keyout "$fixture/key.pem" -out "$fixture/cert.pem" 2>"$fixture/openssl.log"
openssl pkcs12 -export -inkey "$fixture/key.pem" -in "$fixture/cert.pem" -name "$label" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -passout fd:3 \
  -out "$fixture/identity.p12" 3<<< "$password"
identity=$(openssl x509 -in "$fixture/cert.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
[[ "$identity" =~ ^[0-9A-F]{40}$ ]] || die 'Could not identify the generated test certificate'

app="$fixture/SigningTest.app"
mkdir -p "$app/Contents/MacOS"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>example.usagebar.signing-test</string>
<key>CFBundleExecutable</key><string>SigningTest</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
printf 'int main(void) { return 0; }\n' | xcrun clang -x c - -o "$app/Contents/MacOS/SigningTest"

(
  scratch="$fixture/success"
  mkdir "$scratch"
  cp "$fixture/identity.p12" "$scratch/test.p12"
  open_signing_keychain
  import_signing_identity "$scratch/test.p12" "$password" /usr/bin/codesign
  test ! -e "$scratch/test.p12"
  allow_keychain_signing
  identities=$(security find-identity -p codesigning "$keychain")
  [[ "$identities" == *"$identity"* ]] || die 'Test identity not found in the temporary Keychain'
  listed=$(security list-keychains -d user)
  if [[ "$listed" == *""$keychain""* ]]; then
    echo 'The runner automatically registered the temporary Keychain.'
  else
    echo 'The runner did not automatically register the temporary Keychain.'
  fi
  # Probe the previous flow with the same fixture before registering explicitly.
  if codesign --force --keychain "$keychain" --sign "$identity" --options runtime --timestamp=none "$app" >"$scratch/before.log" 2>&1; then
    echo 'Fixture signing also worked before explicit registration.'
  elif grep -Fq 'no identity found' "$scratch/before.log"; then
    echo 'Fixture reproduced codesign no identity found before explicit registration.'
  else
    echo 'Fixture signing failed before explicit registration with a different error.'
  fi
  register_signing_keychain
  listed=$(security list-keychains -d user)
  [[ "$listed" == *""$keychain""* ]] || die 'Temporary Keychain missing from search list'
  # No Apple service is used by this ephemeral certificate.
  codesign --force --keychain "$keychain" --sign "$identity" --options runtime --timestamp=none "$app"
  codesign --verify --deep --strict --verbose=2 "$app"
  signature=$(codesign --display --verbose=4 "$app" 2>&1)
  grep -Fxq "Authority=$label" <<< "$signature"
  grep -Eq '^CodeDirectory .*flags=.*\(.*runtime' <<< "$signature"
)
test ! -e "$fixture/success"
test "$(security list-keychains -d user)" = "$before"
test "$(security default-keychain -d user)" = "$default_before"

set +e
(
  set -e
  scratch="$fixture/failure"
  mkdir "$scratch"
  cp "$fixture/identity.p12" "$scratch/test.p12"
  open_signing_keychain
  register_signing_keychain
  import_signing_identity "$scratch/test.p12" "wrong-$password" /usr/bin/codesign
  exit 0
) >"$fixture/failure.log" 2>&1
status=$?
set -e
test "$status" -eq 1
grep -Fq 'PKCS#12 import failed.' "$fixture/failure.log"
test ! -e "$fixture/failure"
test "$(security list-keychains -d user)" = "$before"
test "$(security default-keychain -d user)" = "$default_before"
echo 'Temporary Keychain signing, strict verification and success/failure cleanup passed.'
