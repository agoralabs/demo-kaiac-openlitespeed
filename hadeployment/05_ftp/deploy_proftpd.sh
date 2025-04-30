#!/bin/bash
# Script robuste de création d'utilisateur SFTP/ProFTPD
set -euo pipefail

# === Configuration ===
DEFAULT_GROUP="ftpusers"
LOG_FILE="/var/log/ftp_user_creation.log"

# === Fonction de journalisation ===
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# === Validation des arguments ===
if [ "$#" -ne 3 ]; then
    echo "ERREUR: Nombre d'arguments incorrect"
    echo "Usage: sudo $0 \"username\" \"password\" \"/chemin/wordpress\""
    echo "Exemple: sudo $0 \"site1_ftp\" \"Mon@Pass123\" \"/var/www/site1\""
    exit 1
fi

# Nettoyage des arguments
USERNAME=$(echo "$1" | tr -d '[:space:]')
PASSWORD="$2"
WP_DIR=$(echo "$3" | sed 's:/*$::')  # Supprime les slashs finaux

# === Validation stricte ===
if [ -z "$USERNAME" ]; then
    echo "ERREUR: Le nom d'utilisateur ne peut pas être vide"
    exit 1
fi

if ! [[ "$USERNAME" =~ ^[a-z][a-z0-9_]{3,20}$ ]]; then
    echo "ERREUR: Nom d'utilisateur invalide. Doit contenir :"
    echo "- Que des minuscules, chiffres et underscores"
    echo "- Commencer par une lettre"
    echo "- 4 à 20 caractères"
    exit 1
fi

if [ ! -d "$WP_DIR" ]; then
    echo "ERREUR: Le répertoire $WP_DIR n'existe pas"
    exit 1
fi

# === Création du groupe si nécessaire ===
if ! getent group "$DEFAULT_GROUP" >/dev/null; then
    groupadd "$DEFAULT_GROUP" || { echo "Échec création groupe"; exit 1; }
    log "Groupe $DEFAULT_GROUP créé"
fi

# === Création de l'utilisateur ===
if id "$USERNAME" &>/dev/null; then
    echo "ERREUR: L'utilisateur $USERNAME existe déjà"
    exit 1
fi

useradd \
  --system \
  --gid "$DEFAULT_GROUP" \
  --home-dir "$WP_DIR" \
  --shell /bin/false \
  "$USERNAME" || { echo "Échec de useradd"; exit 1; }

echo "$USERNAME:$PASSWORD" | chpasswd || { echo "Échec chpasswd"; exit 1; }

# === Configuration des permissions ===
chown -R "$USERNAME:$DEFAULT_GROUP" "$WP_DIR"
find "$WP_DIR" -type d -exec chmod 750 {} \;
find "$WP_DIR" -type f -exec chmod 640 {} \;

# === Configuration ProFTPD ===
if [ -d /etc/proftpd/conf.d ]; then
    cat > "/etc/proftpd/conf.d/$USERNAME.conf" <<EOF
<Directory "$WP_DIR">
    <Limit ALL>
        AllowUser $USERNAME
    </Limit>
</Directory>
EOF
    systemctl reload proftpd
fi

# === Résultat ===
log "Utilisateur $USERNAME créé avec accès à $WP_DIR"
echo "SUCCÈS: Utilisateur créé"
echo "Nom: $USERNAME"
echo "Répertoire: $WP_DIR"
echo "Connexion: sftp -P VOTRE_PORT $USERNAME@$(hostname -I | awk '{print $1}')"