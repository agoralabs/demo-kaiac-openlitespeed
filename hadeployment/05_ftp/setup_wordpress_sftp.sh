#!/bin/bash
# Script de configuration SFTP pour sites WordPress avec OpenLiteSpeed
# Usage: sudo ./setup_wordpress_sftp.sh <site_name> <username> <password> <wp_directory>

set -euo pipefail

# === Configuration ===
SFTP_GROUP="sftpusers"
LOG_FILE="/var/log/wordpress_sftp.log"
SSH_CONFIG="/etc/ssh/sshd_config"
SSH_CONFIG_BACKUP="${SSH_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"

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
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <site_name> <username> <password> [wp_directory]"
    echo "Exemple: $0 monsite client1 password123 /usr/local/lsws/wordpress/monsite"
    exit 1
fi

SITE_NAME="$1"
USERNAME="$2"
PASSWORD="$3"
WP_DIR="${4:-/usr/local/lsws/wordpress/$SITE_NAME}"

# === Validation du nom d'utilisateur ===
if ! [[ "$USERNAME" =~ ^[a-z][a-z0-9_]{2,19}$ ]]; then
    echo "ERREUR: Nom d'utilisateur invalide. Doit contenir:"
    echo "- Uniquement des lettres minuscules, chiffres et underscores"
    echo "- Commencer par une lettre"
    echo "- Entre 3 et 20 caractères"
    exit 1
fi

# === Configuration initiale SFTP si nécessaire ===
if ! getent group "$SFTP_GROUP" >/dev/null; then
    log "Configuration initiale SFTP..."
    
    # Installation des paquets nécessaires
    apt update
    apt install -y openssh-server fail2ban
    
    # Création du groupe SFTP
    groupadd "$SFTP_GROUP"
    
    # Sauvegarde de la configuration SSH
    cp "$SSH_CONFIG" "$SSH_CONFIG_BACKUP"
    
    # Configuration SFTP
    if ! grep -q "^Subsystem sftp internal-sftp" "$SSH_CONFIG"; then
        sed -i 's/^Subsystem\s\+sftp.*/Subsystem sftp internal-sftp/' "$SSH_CONFIG"
        
        cat >> "$SSH_CONFIG" <<EOF

# Configuration SFTP avec chroot
Match Group $SFTP_GROUP
    ChrootDirectory %h
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
    PasswordAuthentication yes
EOF
    fi
    
    # Redémarrage du service SSH
    systemctl restart sshd
    
    # Configuration de fail2ban pour SFTP
    cat > /etc/fail2ban/jail.d/sftp.conf <<EOF
[sftp]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
EOF
    
    systemctl restart fail2ban
    log "Configuration SFTP initiale terminée"
fi

# === Vérification si l'utilisateur existe déjà ===
if id "$USERNAME" &>/dev/null; then
    echo "ERREUR: L'utilisateur $USERNAME existe déjà"
    exit 1
fi

# === Vérification du répertoire WordPress ===
if [ ! -d "$WP_DIR" ]; then
    echo "ERREUR: Le répertoire WordPress $WP_DIR n'existe pas"
    echo "Voulez-vous le créer? (o/n)"
    read -r response
    if [[ "$response" =~ ^[Oo]$ ]]; then
        mkdir -p "$WP_DIR"
        log "Répertoire WordPress $WP_DIR créé"
    else
        echo "Opération annulée"
        exit 1
    fi
fi

# === Création de l'utilisateur ===
log "Création de l'utilisateur SFTP $USERNAME pour le site $SITE_NAME..."
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
log "Liaison du répertoire WordPress $WP_DIR..."

# Option 1: Lien symbolique (plus simple mais moins sécurisé)
# ln -sf "$WP_DIR" "/home/$USERNAME/www/wordpress"
# chown -h "$USERNAME:$USERNAME" "/home/$USERNAME/www/wordpress"

# Option 2: Mount bind (plus sécurisé)
mount --bind "$WP_DIR" "/home/$USERNAME/www"
echo "$WP_DIR /home/$USERNAME/www none bind 0 0" >> /etc/fstab

# Ajustement des permissions
chown -R "$USERNAME:$USERNAME" "$WP_DIR"
chmod -R 755 "$WP_DIR"

log "Utilisateur SFTP $USERNAME créé avec succès pour le site $SITE_NAME"
echo ""
echo "=== CRÉATION UTILISATEUR SFTP RÉUSSIE ==="
echo "Site WordPress: $SITE_NAME"
echo "Nom d'utilisateur: $USERNAME"
echo "Mot de passe: $PASSWORD"
echo "Répertoire WordPress: $WP_DIR"
echo "Répertoire SFTP: /www/"
echo "Connexion: sftp $USERNAME@$(hostname -I | awk '{print $1}')"
echo ""
echo "Note: Le répertoire WordPress est directement accessible à la racine SFTP (/www/)"
