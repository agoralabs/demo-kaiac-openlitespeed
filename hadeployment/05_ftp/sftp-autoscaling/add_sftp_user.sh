#!/bin/bash
# Script d'ajout d'utilisateur SFTP pour WordPress avec SSM Parameter Store
# Usage: sudo ./add_sftp_user.sh <site_name> <username> <password>

set -euo pipefail

# === Configuration ===
PARAMETER_PATH="/sftp/users"
LOG_FILE="/var/log/sftp_management.log"
WP_ROOT="/var/www"
SFTP_SYNC_USERS_SCRIPT="/home/ubuntu/sync_sftp_users.sh"

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
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <site_name> <username> <password>"
    echo "Exemple: $0 monsite client1 password123"
    exit 1
fi

SITE_NAME="$1"
USERNAME="$2"
PASSWORD="$3"
WP_DIR="${WP_ROOT}/${SITE_NAME}"

# === Validation du nom d'utilisateur ===
if ! [[ "$USERNAME" =~ ^[a-z][a-z0-9_]{2,19}$ ]]; then
    echo "ERREUR: Nom d'utilisateur invalide. Doit contenir:"
    echo "- Uniquement des lettres minuscules, chiffres et underscores"
    echo "- Commencer par une lettre"
    echo "- Entre 3 et 20 caractères"
    exit 1
fi

log "Ajout de l'utilisateur SFTP $USERNAME pour le site $SITE_NAME..."

# === Récupérer la liste actuelle des utilisateurs ===
USERS_JSON=$(aws ssm get-parameter --name "$PARAMETER_PATH" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "[]")

# === Vérifier si l'utilisateur existe déjà dans le paramètre ===
if echo "$USERS_JSON" | jq -e ".[] | select(.username == \"$USERNAME\")" >/dev/null 2>&1; then
    echo "ERREUR: L'utilisateur $USERNAME existe déjà dans le paramètre SSM"
    exit 1
fi

# === Ajouter le nouvel utilisateur au paramètre ===
NEW_USER=$(cat <<EOF
{
  "username": "$USERNAME",
  "password": "$PASSWORD",
  "site_name": "$SITE_NAME"
}
EOF
)

UPDATED_USERS=$(echo "$USERS_JSON" | jq ". + [$NEW_USER]")
aws ssm put-parameter --name "$PARAMETER_PATH" --type "SecureString" --value "$UPDATED_USERS" --overwrite >/dev/null

log "Utilisateur $USERNAME ajouté au paramètre SSM"

# === Synchroniser les utilisateurs sur toutes les instances ===
log "Déclenchement de la synchronisation sur toutes les instances..."

# Obtenir la liste des groupes d'autoscaling
ASG_LIST=$(aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[].AutoScalingGroupName" --output text)

if [ -n "$ASG_LIST" ]; then
    for ASG in $ASG_LIST; do
        log "Synchronisation des utilisateurs sur le groupe d'autoscaling $ASG..."
        aws ssm send-command \
            --document-name "AWS-RunShellScript" \
            --targets "Key=tag:aws:autoscaling:groupName,Values=$ASG" \
            --parameters commands="$SFTP_SYNC_USERS_SCRIPT" \
            --comment "Synchronisation des utilisateurs SFTP" \
            --output text
    done
else
    log "Aucun groupe d'autoscaling trouvé, synchronisation sur l'instance locale uniquement"
    $SFTP_SYNC_USERS_SCRIPT
fi

log "Utilisateur SFTP $USERNAME créé avec succès pour le site $SITE_NAME"
echo ""
echo "=== CRÉATION UTILISATEUR SFTP RÉUSSIE ==="
echo "Site WordPress: $SITE_NAME"
echo "Nom d'utilisateur: $USERNAME"
echo "Mot de passe: $PASSWORD"
echo "Répertoire WordPress: $WP_DIR"
echo "Répertoire SFTP: /www/"
echo "Connexion: sftp $USERNAME@<adresse-ip-ou-dns>"
echo ""
echo "Note: L'utilisateur sera disponible sur toutes les instances dans quelques minutes"
