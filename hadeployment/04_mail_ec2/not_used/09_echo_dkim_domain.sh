#!/bin/bash
if [ -z "$1" ]; then
  echo "Usage: $0 <domaine>"
  exit 1
fi

DOMAIN="$1"
MAILCOW_HOST="https://mail.skyscaledev.com"
API_KEY="C28D4F-2ABA7C-D8581D-EDCC97-11692B"

# Ajoute le domaine
curl -X POST -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d "{\"domain\": \"$DOMAIN\"}" "$MAILCOW_HOST/api/v1/add/domain"

# Génère la clé DKIM
curl -X POST -H "X-API-Key: $API_KEY" "$MAILCOW_HOST/api/v1/add/dkim/$DOMAIN"

# Récupère la clé DKIM
DKIM_DATA=$(curl -s -X GET -H "X-API-Key: $API_KEY" "$MAILCOW_HOST/api/v1/get/dkim/$DOMAIN")
echo "DKIM : $DKIM_DATA"