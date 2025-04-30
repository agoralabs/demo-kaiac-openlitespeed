#!/bin/bash
# Script de création d'utilisateur FTP/SFTP avec paramètres personnalisés
# Usage: sudo ./creer-utilisateur-ftp.sh [login] [password] [/chemin/absolu/home]

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
    echo "Usage: $0 [login] [password] [/chemin/absolu/home]"
    echo "Exemple: $0 site4_skyscaledev_com_ftp_usr MonP@ssw0rd! /var/www/site4_skyscaledev_com"
    exit 1
fi

LOGIN="$1"
PASSWORD="$2"
HOME_DIR="$3"


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
    --home-dir "$HOME_DIR" \
    --shell /bin/false \
    "$LOGIN"

echo "$LOGIN:$PASSWORD" | chpasswd

# === Création de l'arborescence ===
mkdir -p "$HOME_DIR"
chown "$LOGIN:$DEFAULT_GROUP" "$HOME_DIR"
chmod 750 "$HOME_DIR"

# Dossier WordPress par défaut
WP_DIR="$HOME_DIR/www"
mkdir -p "$WP_DIR"
chown "$LOGIN:$DEFAULT_GROUP" "$WP_DIR"
chmod 770 "$WP_DIR"

# === Configuration ProFTPD (si nécessaire) ===
if [ -d /etc/proftpd/conf.d ]; then
    cat > "/etc/proftpd/conf.d/$LOGIN.conf" <<EOF
<Directory "$HOME_DIR">
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
echo "Home directory: $HOME_DIR"
echo "Dossier WordPress: $WP_DIR"
echo "UID/GID: $NEW_UID/$(getent group "$DEFAULT_GROUP" | cut -d: -f3)"
echo "Connectez-vous avec:"
echo "sftp -P 22 $LOGIN@$(hostname -I | awk '{print $1}')"