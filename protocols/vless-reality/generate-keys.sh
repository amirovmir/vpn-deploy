#!/bin/bash
set -e

# Pull image once silently, then run subcommands
docker pull teddysun/xray:latest >/dev/null 2>&1

KEYS=$(docker run --rm teddysun/xray xray x25519 2>/dev/null)
PRIVATE=$(echo "$KEYS" | grep "Private key:" | awk '{print $NF}')
PUBLIC=$(echo "$KEYS"  | grep "Public key:"  | awk '{print $NF}')

UUID=$(docker run --rm teddysun/xray xray uuid 2>/dev/null | tr -d '[:space:]')
SHORT_ID=$(openssl rand -hex 4)

printf '{"privateKey":"%s","publicKey":"%s","uuid":"%s","shortId":"%s"}\n' \
    "$PRIVATE" "$PUBLIC" "$UUID" "$SHORT_ID"
