#!/bin/bash
# Script de suppression d'utilisateur SFTP qui va être exécuté sur toutes les instances

set -euo pipefail

# === Configuration ===
LOG_FILE="/var/log/sftp_management.log"


# === Fonction de journalisation ===
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

USERNAME="$1"

log "Suppression de l'utilisateur SFTP $USERNAME..."

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

log "Utilisateur SFTP $USERNAME supprimé avec succès"