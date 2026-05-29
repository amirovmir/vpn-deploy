#!/bin/bash
set -e

# Required env vars: CF_TOKEN, DOMAIN, SERVER_IP
log() { echo "[hysteria2] $*" >&2; }

ROOT_DOMAIN=$(echo "$DOMAIN" | rev | cut -d. -f1-2 | rev)

# 1. Get Cloudflare Zone ID
ZONE_ID=$(curl -sf "https://api.cloudflare.com/client/v4/zones?name=$ROOT_DOMAIN" \
    -H "Authorization: Bearer $CF_TOKEN" | \
    python3 -c "import json,sys; print(json.load(sys.stdin)['result'][0]['id'])")
log "Zone: $ROOT_DOMAIN ($ZONE_ID)"

# 2. Upsert A record DOMAIN → SERVER_IP
EXISTING=$(curl -sf \
    "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$DOMAIN&type=A" \
    -H "Authorization: Bearer $CF_TOKEN")
RECORD_ID=$(echo "$EXISTING" | python3 -c \
    "import json,sys; r=json.load(sys.stdin)['result']; print(r[0]['id'] if r else '')" 2>/dev/null || true)

DNS_PAYLOAD="{\"type\":\"A\",\"name\":\"$DOMAIN\",\"content\":\"$SERVER_IP\",\"ttl\":60,\"proxied\":false}"
if [ -n "$RECORD_ID" ]; then
    log "Updating A record $DOMAIN -> $SERVER_IP"
    curl -sf -X PUT \
        "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
        -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" \
        -d "$DNS_PAYLOAD" > /dev/null
else
    log "Creating A record $DOMAIN -> $SERVER_IP"
    curl -sf -X POST \
        "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" \
        -d "$DNS_PAYLOAD" > /dev/null
fi

# 3. Install acme.sh if needed
if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
    log "Installing acme.sh..."
    curl -sf https://get.acme.sh | sh -s email="admin@$ROOT_DOMAIN" > /dev/null 2>&1
fi
ACME="$HOME/.acme.sh/acme.sh"

# 4. Issue or renew TLS cert (ECC) via Cloudflare DNS challenge
export CF_Token="$CF_TOKEN"
export CF_Zone_ID="$ZONE_ID"

CERT_ECC="$HOME/.acme.sh/${DOMAIN}_ecc"

if [ -f "$CERT_ECC/fullchain.cer" ]; then
    log "Certificate exists, renewing if due..."
    "$ACME" --renew -d "$DOMAIN" --ecc > /dev/null 2>&1 || true
else
    log "Issuing TLS certificate for $DOMAIN..."
    "$ACME" --issue --dns dns_cf -d "$DOMAIN" \
        --server letsencrypt --keylength ec-256 > /dev/null 2>&1
fi

# 5. Install cert to /etc/hysteria/
mkdir -p /etc/hysteria
"$ACME" --install-cert -d "$DOMAIN" --ecc \
    --cert-file /etc/hysteria/server.crt \
    --key-file  /etc/hysteria/server.key \
    --reloadcmd "docker restart hysteria2-vpn 2>/dev/null || true" > /dev/null 2>&1
log "Certificate installed to /etc/hysteria/"

# 6. Generate auth password
PASSWORD=$(openssl rand -hex 16)

printf '{"password":"%s","domain":"%s"}\n' "$PASSWORD" "$DOMAIN"
