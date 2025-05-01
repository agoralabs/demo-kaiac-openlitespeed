#!/bin/bash
# Script de déploiement SFTP pour serveurs EC2 Ubuntu en autoscaling
# Ce script configure un serveur SFTP sécurisé avec chroot pour WordPress
# Usage: sudo ./deploy_sftp_autoscaling.sh

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
apt install -y openssh-server fail2ban

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

# === Création du script d'ajout d'utilisateur ===
log "Création du script d'ajout d'utilisateur SFTP..."
cat > /usr/local/bin/add_sftp_user.sh <<'EOF'
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
EOF

chmod +x /usr/local/bin/add_sftp_user.sh
log "Script d'ajout d'utilisateur créé: /usr/local/bin/add_sftp_user.sh"

# === Création d'un utilisateur de test ===
log "Création d'un utilisateur SFTP de test..."
RANDOM_SUFFIX=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 3)
TEST_USER="ftpuser_${RANDOM_SUFFIX}"
TEST_PASSWORD=$(tr -dc 'a-zA-Z0-9!@#$%^&*()_+' < /dev/urandom | head -c 12)
TEST_DIR="/var/www/html/test_${RANDOM_SUFFIX}"

mkdir -p "$TEST_DIR"
/usr/local/bin/add_sftp_user.sh "$TEST_USER" "$TEST_PASSWORD" "$TEST_DIR"

# === Résumé de l'installation ===
echo ""
echo "=== INSTALLATION SFTP RÉUSSIE ==="
echo "Port SFTP: 22"
echo "Utilisateur test: $TEST_USER"
echo "Mot de passe test: $TEST_PASSWORD"
echo "Test de connexion: sftp $TEST_USER@$(hostname -I | awk '{print $1}')"
echo ""
echo "Pour ajouter un nouvel utilisateur:"
echo "sudo /usr/local/bin/add_sftp_user.sh <username> <password> <wp_directory>"
echo ""
echo "Configuration terminée!"
