#!/bin/bash

# Vérification des paramètres
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <KAIAC_API_HOST> <RECORD_NAME> <TOP_DOMAIN>"
    exit 1
fi

KAIAC_API_HOST="https://api.kaiac.io"
RECORD_NAME="$1"
TOP_DOMAIN="$2"

# Exécution de la requête cURL
curl --location "${KAIAC_API_HOST}/api/website/update-is-processing-site" \
--header "Content-Type: application/json" \
--data "{
    \"record\": \"${RECORD_NAME}\",
    \"domain\": \"${TOP_DOMAIN}\"
}"

# Vérification du code de retour
if [ $? -eq 0 ]; then
    echo "Requête exécutée avec succès"
else
    echo "Erreur lors de l'exécution de la requête"
    exit 1
fi