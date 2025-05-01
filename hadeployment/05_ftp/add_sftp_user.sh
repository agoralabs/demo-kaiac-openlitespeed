#!/bin/bash
# Script d'ajout d'utilisateur SFTP pour WordPress
# Usage: sudo ./add_sftp_user.sh <username> <password> <wp_directory>

set -euo pipefail

# === Configuration ===
SFTP_GROUP="sftpusers"
LOG_FILE="/var/log/sftp_user_creation.log"

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
    echo "Usage: $0 <username> <password> <wp_directory>"
    echo "Exemple: $0 client1 password123 /var/www/html/client1"
    exit 1
fi

USERNAME="$1"
PASSWORD="$2"
WP_DIR="$3"

# === Validation du nom d'utilisateur ===
if ! [[ "$USERNAME" =~ ^[a-z][a-z0-9_]{2,19}$ ]]; then
    echo "ERREUR: Nom d'utilisateur invalide. Doit contenir:"
    echo "- Uniquement des lettres minuscules, chiffres et underscores"
    echo "- Commencer par une lettre"
    echo "- Entre 3 et 20 caractères"
    exit 1
fi

# === Vérification si l'utilisateur existe déjà ===
if id "$USERNAME" &>/dev/null; then
    echo "ERREUR: L'utilisateur $USERNAME existe déjà"
    exit 1
fi

# === Création du répertoire WordPress si nécessaire ===
if [ ! -d "$WP_DIR" ]; then
    mkdir -p "$WP_DIR"
    log "Répertoire WordPress $WP_DIR créé"
fi

# === Création de l'utilisateur ===
log "Création de l'utilisateur SFTP $USERNAME..."
useradd -m -G "$SFTP_GROUP" -s /bin/false "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd

# === Configuration des permissions ===
log "Configuration des permissions..."
chown root:root "/home/$USERNAME"
chmod 755 "/home/$USERNAME"

# === Création du répertoire www ===
mkdir -p "/home/$USERNAME/www"
chown "$USERNAME:$USERNAME" "/home/$USERNAME/www"

# === Liaison du répertoire WordPress ===
if [ -d "$WP_DIR" ]; then
    # Créer un lien symbolique du répertoire WordPress vers le répertoire www de l'utilisateur
    ln -sf "$WP_DIR" "/home/$USERNAME/www/wordpress"
    chown -h "$USERNAME:$USERNAME" "/home/$USERNAME/www/wordpress"
    log "Lien symbolique créé: /home/$USERNAME/www/wordpress -> $WP_DIR"
fi

log "Utilisateur SFTP $USERNAME créé avec succès"
echo "=== CRÉATION UTILISATEUR SFTP RÉUSSIE ==="
echo "Nom d'utilisateur: $USERNAME"
echo "Mot de passe: $PASSWORD"
echo "Répertoire SFTP: /www/"
echo "Répertoire WordPress: /www/wordpress/"
echo "Connexion: sftp -P 22 $USERNAME@$(hostname -I | awk '{print $1}')"
