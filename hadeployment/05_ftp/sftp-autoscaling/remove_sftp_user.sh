#!/bin/bash
# Script de suppression d'utilisateur SFTP pour WordPress avec SSM Parameter Store
# Usage: sudo ./remove_sftp_user.sh <username>

set -euo pipefail

# === Configuration ===
PARAMETER_PATH="/sftp/users"
LOG_FILE="/var/log/sftp_management.log"
ASG_NAME="ols-web-prod-asg"
SFTP_SYNC_REMOVE_USER_SCRIPT="/home/ubuntu/sync_remove_sftp_user.sh"

# === Fonction de journalisation ===
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# === Vérification des privilèges root ===
if [ "$(id -u)" -ne 0 ]; then
    echo "ERREUR: Ce script doit être exécuté en tant que root"
    exit 1
fi

# === Validation des arguments ===
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <username>"
    echo "Exemple: $0 client1"
    exit 1
fi

USERNAME="$1"

log "Suppression de l'utilisateur SFTP $USERNAME..."

# === Récupérer la liste actuelle des utilisateurs ===
USERS_JSON=$(aws ssm get-parameter --name "$PARAMETER_PATH" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "[]")

# === Vérifier si l'utilisateur existe dans le paramètre ===
if ! echo "$USERS_JSON" | jq -e ".[] | select(.username == \"$USERNAME\")" >/dev/null 2>&1; then
    echo "ERREUR: L'utilisateur $USERNAME n'existe pas dans le paramètre SSM"
    exit 1
fi

# === Supprimer l'utilisateur du paramètre ===
UPDATED_USERS=$(echo "$USERS_JSON" | jq "map(select(.username != \"$USERNAME\"))")
aws ssm put-parameter --name "$PARAMETER_PATH" --type "SecureString" --value "$UPDATED_USERS" --overwrite >/dev/null

log "Utilisateur $USERNAME supprimé du paramètre SSM"

# === Synchroniser la suppression sur toutes les instances ===
log "Déclenchement de la suppression sur toutes les instances..."

log "Suppression de l'utilisateur sur le groupe d'autoscaling $ASG_NAME..."
aws ssm send-command \
    --document-name "AWS-RunShellScript" \
    --targets "Key=tag:aws:autoscaling:groupName,Values=$ASG_NAME" \
    --parameters commands="$SFTP_SYNC_REMOVE_USER_SCRIPT $USERNAME" \
    --comment "Synchronisation des utilisateurs SFTP" \
    --output text

log "Utilisateur SFTP $USERNAME supprimé avec succès"
echo ""
echo "=== SUPPRESSION UTILISATEUR SFTP RÉUSSIE ==="
echo "Nom d'utilisateur: $USERNAME"
echo ""
echo "Note: L'utilisateur sera supprimé de toutes les instances dans quelques minutes"
