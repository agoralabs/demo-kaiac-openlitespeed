#!/bin/bash
# Script de listage des utilisateurs SFTP depuis SSM Parameter Store
# Usage: ./list_sftp_users.sh

set -euo pipefail

# === Configuration ===
PARAMETER_PATH="/sftp/users"

# === Récupérer la liste des utilisateurs ===
USERS_JSON=$(aws ssm get-parameter --name "$PARAMETER_PATH" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "[]")

# === Afficher les utilisateurs ===
echo "=== UTILISATEURS SFTP ==="
echo ""

if [ "$USERS_JSON" = "[]" ]; then
    echo "Aucun utilisateur SFTP configuré"
    exit 0
fi

# Compter le nombre d'utilisateurs
USER_COUNT=$(echo "$USERS_JSON" | jq '. | length')
echo "Nombre total d'utilisateurs: $USER_COUNT"
echo ""

# Afficher les détails de chaque utilisateur
echo "$USERS_JSON" | jq -r '.[] | "Utilisateur: \(.username)\nSite WordPress: \(.site_name)\n---"'
