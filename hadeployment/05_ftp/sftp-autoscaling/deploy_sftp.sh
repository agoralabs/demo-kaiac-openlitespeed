#!/bin/bash
# Script de déploiement SFTP pour serveurs EC2 Ubuntu en autoscaling
# Ce script configure un serveur SFTP sécurisé avec chroot pour WordPress
# Usage: sudo ./deploy_sftp.sh

set -euo pipefail

# === Configuration ===
SFTP_GROUP="sftpusers"
LOG_FILE="/var/log/sftp_deployment.log"
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

log "Début de la configuration SFTP pour WordPress"

# === Installation des paquets nécessaires ===
log "Installation des paquets requis..."
apt update
apt install -y openssh-server fail2ban jq awscli

# === Création du groupe SFTP ===
log "Création du groupe SFTP..."
if ! getent group "$SFTP_GROUP" >/dev/null; then
    groupadd "$SFTP_GROUP"
    log "Groupe $SFTP_GROUP créé"
else
    log "Le groupe $SFTP_GROUP existe déjà"
fi

# === Sauvegarde de la configuration SSH ===
log "Sauvegarde de la configuration SSH..."
cp "$SSH_CONFIG" "$SSH_CONFIG_BACKUP"
log "Configuration SSH sauvegardée dans $SSH_CONFIG_BACKUP"

# === Configuration SFTP ===
log "Configuration du serveur SFTP..."

# Vérifier si la configuration SFTP existe déjà
if grep -q "^Subsystem sftp internal-sftp" "$SSH_CONFIG"; then
    log "La configuration SFTP existe déjà"
else
    # Remplacer la ligne Subsystem sftp existante
    sed -i 's/^Subsystem\s\+sftp.*/Subsystem sftp internal-sftp/' "$SSH_CONFIG"
    
    # Ajouter la configuration SFTP si elle n'existe pas
    if ! grep -q "Match Group $SFTP_GROUP" "$SSH_CONFIG"; then
        cat >> "$SSH_CONFIG" <<EOF

# Configuration SFTP avec chroot
Match Group $SFTP_GROUP
    ChrootDirectory %h
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
    PasswordAuthentication yes
EOF
        log "Configuration SFTP ajoutée au fichier sshd_config"
    fi
fi

# === Redémarrage du service SSH ===
log "Redémarrage du service SSH..."
systemctl restart sshd
log "Service SSH redémarré"

# === Configuration de fail2ban pour SFTP ===
log "Configuration de fail2ban pour SFTP..."
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
log "Fail2ban configuré pour protéger SFTP"

# === Résumé de l'installation ===
echo ""
echo "=== INSTALLATION SFTP RÉUSSIE ==="
echo "Port SFTP: 22"
echo "Groupe SFTP: $SFTP_GROUP"
echo ""
echo "Pour synchroniser les utilisateurs:"
echo "sudo./sync_sftp_users.sh"
echo ""
echo "Configuration terminée!"
