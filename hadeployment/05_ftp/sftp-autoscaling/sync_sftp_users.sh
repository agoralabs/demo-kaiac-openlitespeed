#!/bin/bash
# Script de synchronisation des utilisateurs SFTP depuis SSM Parameter Store

set -euo pipefail

# Variables
SFTP_GROUP="sftpusers"
WP_ROOT="/var/www"
PARAMETER_PATH="/sftp/users"
LOG_FILE="/var/log/sftp_sync.log"

# Fonction de journalisation
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Vérification des privilèges root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERREUR: Ce script doit être exécuté en tant que root"
    exit 1
fi

log "Début de la synchronisation des utilisateurs SFTP"

# Récupérer la liste des utilisateurs depuis SSM Parameter Store
USERS_JSON=$(aws ssm get-parameter --name "$PARAMETER_PATH" --with-decryption --query "Parameter.Value" --output text 2>/dev/null || echo "[]")

# Traiter chaque utilisateur
echo "$USERS_JSON" | jq -c '.[]' 2>/dev/null | while read -r user; do
    username=$(echo "$user" | jq -r '.username')
    password=$(echo "$user" | jq -r '.password')
    site_name=$(echo "$user" | jq -r '.site_name')
    wp_dir="${WP_ROOT}/${site_name}"
    
    # Vérifier si l'utilisateur existe déjà
    if ! id "$username" &>/dev/null; then
        log "Création de l'utilisateur SFTP $username pour le site $site_name..."
        
        # Créer l'utilisateur
        useradd -m -G "$SFTP_GROUP" -s /bin/false "$username"
        echo "$username:$password" | chpasswd
        
        # Configurer les permissions
        chown root:root "/home/$username"
        chmod 755 "/home/$username"
        
        # Créer le répertoire WordPress si nécessaire
        if [ ! -d "$wp_dir" ]; then
            mkdir -p "$wp_dir"
            log "Répertoire WordPress $wp_dir créé"
        fi
        
        # Créer le répertoire www
        mkdir -p "/home/$username/www"
        
        # Configurer le bind mount
        if ! grep -q "$wp_dir /home/$username/www" /etc/fstab; then
            echo "$wp_dir /home/$username/www none bind 0 0" >> /etc/fstab
            mount --bind "$wp_dir" "/home/$username/www"
            log "Montage bind configuré: $wp_dir -> /home/$username/www"
        fi
        
        # Ajuster les permissions
        chown -R "$username:$username" "$wp_dir"
        chown "$username:$username" "/home/$username/www"
        chmod -R 755 "$wp_dir"
        
        log "Utilisateur SFTP $username créé avec succès"
    else
        log "L'utilisateur $username existe déjà"
    fi
done

log "Synchronisation des utilisateurs SFTP terminée"
