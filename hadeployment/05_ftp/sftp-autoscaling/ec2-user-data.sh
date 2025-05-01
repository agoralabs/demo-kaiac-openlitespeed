#!/bin/bash
# Script d'initialisation EC2 pour la configuration SFTP
# À utiliser dans le user-data de votre modèle de lancement

# === Configuration ===
SCRIPTS_DIR="/opt/sftp-autoscaling"
EFS_ID="fs-xxxxxxxx" # Remplacez par votre ID de système de fichiers EFS
EFS_REGION="us-west-2" # Remplacez par votre région AWS
EFS_MOUNT="/mnt/efs"
WP_ROOT="/usr/local/lsws/wordpress"

# === Installation des paquets nécessaires ===
apt update
apt install -y nfs-common jq awscli openssh-server fail2ban

# === Création du répertoire pour les scripts ===
mkdir -p "$SCRIPTS_DIR"

# === Montage EFS ===
mkdir -p "$EFS_MOUNT"
echo "${EFS_ID}.efs.${EFS_REGION}.amazonaws.com:/ $EFS_MOUNT nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport 0 0" >> /etc/fstab
mount -a

# === Lien symbolique vers le répertoire WordPress ===
mkdir -p $(dirname "$WP_ROOT")
ln -sf "$EFS_MOUNT/wordpress" "$WP_ROOT"

# === Téléchargement des scripts ===
# Note: Dans un environnement de production, stockez ces scripts dans S3 et téléchargez-les
cat > "$SCRIPTS_DIR/deploy_sftp.sh" <<'EOF'
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
EFS_MOUNT="/mnt/efs"
WP_ROOT="/usr/local/lsws/wordpress"
SCRIPTS_DIR="/opt/sftp-autoscaling"

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

# === Montage EFS si ce n'est pas déjà fait ===
if ! mountpoint -q "$EFS_MOUNT"; then
    log "Le point de montage EFS n'est pas monté. Vérifiez votre configuration EFS."
    log "Assurez-vous que EFS est monté sur $EFS_MOUNT"
    
    # Créer le répertoire de montage si nécessaire
    if [ ! -d "$EFS_MOUNT" ]; then
        mkdir -p "$EFS_MOUNT"
        log "Répertoire de montage EFS créé: $EFS_MOUNT"
    fi
    
    # Note: Le montage EFS devrait être configuré dans /etc/fstab ou via user-data
    log "Vous devez configurer le montage EFS dans /etc/fstab ou via user-data"
fi

# === Lien symbolique vers le répertoire WordPress si nécessaire ===
if [ ! -d "$WP_ROOT" ]; then
    mkdir -p $(dirname "$WP_ROOT")
    ln -sf "$EFS_MOUNT/wordpress" "$WP_ROOT"
    log "Lien symbolique créé: $WP_ROOT -> $EFS_MOUNT/wordpress"
fi

# === Création du répertoire pour les scripts ===
mkdir -p "$SCRIPTS_DIR"
log "Répertoire pour les scripts créé: $SCRIPTS_DIR"

# === Synchronisation des utilisateurs existants ===
log "Synchronisation des utilisateurs SFTP existants..."
cat > "$SCRIPTS_DIR/sync_sftp_users.sh" <<'EOF'
#!/bin/bash
# Script de synchronisation des utilisateurs SFTP depuis SSM Parameter Store

set -euo pipefail

# Variables
SFTP_GROUP="sftpusers"
WP_ROOT="/usr/local/lsws/wordpress"
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
EOF

chmod +x "$SCRIPTS_DIR/sync_sftp_users.sh"
log "Script de synchronisation créé: $SCRIPTS_DIR/sync_sftp_users.sh"

# === Exécution de la synchronisation initiale ===
"$SCRIPTS_DIR/sync_sftp_users.sh"

# === Résumé de l'installation ===
echo ""
echo "=== INSTALLATION SFTP RÉUSSIE ==="
echo "Port SFTP: 22"
echo "Groupe SFTP: $SFTP_GROUP"
echo "Répertoire WordPress: $WP_ROOT"
echo "Répertoire des scripts: $SCRIPTS_DIR"
echo ""
echo "Pour synchroniser les utilisateurs:"
echo "sudo $SCRIPTS_DIR/sync_sftp_users.sh"
echo ""
echo "Configuration terminée!"
EOF

chmod +x "$SCRIPTS_DIR/deploy_sftp.sh"

# === Exécution du script de déploiement ===
"$SCRIPTS_DIR/deploy_sftp.sh"

# === Configuration de la synchronisation périodique ===
echo "*/5 * * * * root $SCRIPTS_DIR/sync_sftp_users.sh >/dev/null 2>&1" > /etc/cron.d/sftp_sync
