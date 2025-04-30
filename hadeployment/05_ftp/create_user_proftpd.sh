#!/bin/bash
# Script de création d'utilisateur SFTP avec home directory = répertoire WordPress
# Usage: sudo ./creer-utilisateur-ftp.sh [login] [password] [/chemin/absolu/wordpress]

set -euo pipefail

# === Configuration système ===
DEFAULT_GROUP="ftpusers"                  # Groupe FTP
LOG_FILE="/var/log/ftp_user_creation.log" # Fichier de log

# === Vérification root ===
if [ "$(id -u)" -ne 0 ]; then
    echo "ERREUR: Ce script doit être exécuté en tant que root" >&2
    exit 1
fi

# === Validation des arguments ===
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 [login] [password] [/chemin/absolu/wordpress]"
    echo "Exemple: $0 site4_ftp MonP@ssw0rd! /var/www/site4/wp-content"
    exit 1
fi

LOGIN="$1"
PASSWORD="$2"
WP_DIR="$3"

# === Vérification du répertoire WordPress ===
if [ ! -d "$WP_DIR" ]; then
    echo "ERREUR: Le répertoire WordPress $WP_DIR n'existe pas" >&2
    exit 1
fi

# === Création du groupe si inexistant ===
if ! getent group "$DEFAULT_GROUP" >/dev/null; then
    groupadd "$DEFAULT_GROUP"
    echo "Groupe $DEFAULT_GROUP créé"
fi

# === Trouver le prochain UID disponible ===
LAST_UID=$(getent passwd | awk -F: '{print $3}' | sort -n | tail -1)
NEW_UID=$((LAST_UID + 1))

# === Journalisation ===
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# === Création de l'utilisateur ===
log "Début création utilisateur $LOGIN"
if id "$LOGIN" &>/dev/null; then
    echo "ERREUR: L'utilisateur $LOGIN existe déjà" >&2
    exit 1
fi

useradd \
    --system \
    --uid "$NEW_UID" \
    --gid "$DEFAULT_GROUP" \
    --home-dir "$WP_DIR" \  # Le home devient directement le répertoire WordPress
    --shell /bin/false \
    "$LOGIN"

echo "$LOGIN:$PASSWORD" | chpasswd

# === Configuration des permissions ===
chown -R "$LOGIN:$DEFAULT_GROUP" "$WP_DIR"
find "$WP_DIR" -type d -exec chmod 750 {} \;
find "$WP_DIR" -type f -exec chmod 640 {} \;

# === Configuration ProFTPD ===
if [ -d /etc/proftpd/conf.d ]; then
    cat > "/etc/proftpd/conf.d/$LOGIN.conf" <<EOF
<Directory "$WP_DIR">
    <Limit ALL>
        AllowUser $LOGIN
    </Limit>
</Directory>
EOF
    systemctl reload proftpd
fi

# === Résumé ===
log "Utilisateur $LOGIN créé avec UID $NEW_UID"
echo "=== CRÉATION RÉUSSIE ==="
echo "Login: $LOGIN"
echo "Mot de passe: $PASSWORD"
echo "Répertoire WordPress: $WP_DIR"
echo "UID/GID: $NEW_UID/$(getent group "$DEFAULT_GROUP" | cut -d: -f3)"
echo "Connectez-vous avec:"
echo "sftp -P 22 $LOGIN@$(hostname -I | awk '{print $1}')"