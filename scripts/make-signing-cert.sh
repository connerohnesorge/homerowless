#!/usr/bin/env bash
# Creates the self-signed HomerowlessDev code-signing identity in the login keychain.
set -euo pipefail
if security find-identity -v -p codesigning | grep -q HomerowlessDev; then
  echo "HomerowlessDev already exists"; exit 0; fi
TMP=$(mktemp -d)
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=HomerowlessDev
[ext]
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
basicConstraints=critical,CA:false
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/dev.p12" -passout pass:homerowless -legacy 2>/dev/null || \
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/dev.p12" -passout pass:homerowless
security import "$TMP/dev.p12" -k ~/Library/Keychains/login.keychain-db -P homerowless -T /usr/bin/codesign -T /usr/bin/security
security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db "$TMP/cert.pem" 2>/dev/null || \
  echo "note: could not auto-trust cert; open Keychain Access, find HomerowlessDev, set Code Signing to Always Trust"
rm -rf "$TMP"
security find-identity -v -p codesigning | grep HomerowlessDev
