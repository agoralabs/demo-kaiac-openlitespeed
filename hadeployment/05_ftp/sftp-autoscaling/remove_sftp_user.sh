#!/bin/bash
# Script de suppression d'utilisateur SFTP pour WordPress avec SSM Parameter Store
# Usage: sudo ./remove_sftp_user.sh <username>

set -euo pipefail

# === Configuration ===
PARAMETER_PATH="/sftp/users"
LOG_FILE="/var/log/sftp_management.log"

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

# === Créer un script de suppression pour toutes les instances ===
TEMP_SCRIPT=$(mktemp)
cat > "$TEMP_SCRIPT" <<EOF
#!/bin/bash
# Script temporaire de suppression d'utilisateur SFTP

# Vérifier si l'utilisateur existe
if id "$USERNAME" &>/dev/null; then
    # Démonter le répertoire www s'il est monté
    if grep -q "/home/$USERNAME/www" /etc/fstab; then
        umount "/home/$USERNAME/www" 2>/dev/null || true
        sed -i "\|/home/$USERNAME/www|d" /etc/fstab
    fi
    
    # Supprimer l'utilisateur et son répertoire home
    userdel -r "$USERNAME" 2>/dev/null || true
    echo "Utilisateur $USERNAME supprimé"
else
    echo "L'utilisateur $USERNAME n'existe pas sur cette instance"
fi
EOF

# === Synchroniser la suppression sur toutes les instances ===
log "Déclenchement de la suppression sur toutes les instances..."

# Obtenir la liste des groupes d'autoscaling
ASG_LIST=$(aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[].AutoScalingGroupName" --output text)

if [ -n "$ASG_LIST" ]; then
    for ASG in $ASG_LIST; do
        log "Suppression de l'utilisateur sur le groupe d'autoscaling $ASG..."
        aws ssm send-command \
            --document-name "AWS-RunShellScript" \
            --targets "Key=tag:aws:autoscaling:groupName,Values=$ASG" \
            --parameters commands="$(cat $TEMP_SCRIPT)" \
            --comment "Suppression de l'utilisateur SFTP $USERNAME" \
            --output text
    done
else
    log "Aucun groupe d'autoscaling trouvé, suppression sur l'instance locale uniquement"
    bash "$TEMP_SCRIPT"
fi

# Nettoyer le script temporaire
rm -f "$TEMP_SCRIPT"

log "Utilisateur SFTP $USERNAME supprimé avec succès"
echo ""
echo "=== SUPPRESSION UTILISATEUR SFTP RÉUSSIE ==="
echo "Nom d'utilisateur: $USERNAME"
echo ""
echo "Note: L'utilisateur sera supprimé de toutes les instances dans quelques minutes"
